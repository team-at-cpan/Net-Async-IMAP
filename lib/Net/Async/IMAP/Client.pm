package Net::Async::IMAP::Client;
use strict;
use warnings;
use parent qw{IO::Async::Protocol::Stream Protocol::IMAP::Client};

use IO::Async::SSL;
use Socket;
our $VERSION = '0.001';

=head1 NAME

Net::Async::IMAP::Client - asynchronous IMAP client based on L<Protocol::IMAP::Client> and L<IO::Async::Protocol::Stream>.

=head1 SYNOPSIS

 use IO::Async::Loop;
 use Net::Async::IMAP;
 my $loop = IO::Async::Loop->new;
 my $imap = Net::Async::IMAP::Client->new(
 	loop => $loop,
	host => 'mailserver.com',
	service => 'imap',
	user => 'user@mailserver.com',
	pass => 'password',

# Automatically retrieve any new messages that arrive on the server
	on_message_received => sub {
		my ($self, $id) = @_;
		$self->fetch($id);
	},

# Display the subject whenever we have a successful FETCH command
	on_message => sub {
		my ($self, $msg) = @_;
		warn "Had message " . Email::Simple->new($msg)->header('Subject') . "\n";
	},
 );
 $loop->loop_forever;

=head1 DESCRIPTION

Provides support for communicating with IMAP servers under L<IO::Async>.

See L<Protocol::IMAP> for more details on this implementation of IMAP, and RFC3501
for the official protocol specification.

=head1 METHODS

=cut

=head2 new

Instantiate a new object. Will add to the event loop if the loop parameter is passed.

=cut

sub new {
	my $class = shift;
	my %args = @_;

# Clear any options that will cause the parent class to complain
	my $loop = delete $args{loop};

	my $self = $class->SUPER::new( %args );

# Automatically add to the event loop if we were passed one
	$loop->add($self) if $loop;
	return $self;
}

=head2 on_read

Pass any new data into the protocol handler.

=cut

sub on_read {
	my ($self, $buffref, $closed) = @_;
	$self->debug("Stream was closed, this was not expected") if $closed;

# We'll be called again, don't know where, don't know when, but the rest of our data will be waiting for us
	if($$buffref =~ s/^(.*[\n\r]+)//) {
		if($self->is_multi_line) {
			$self->on_multi_line($1);
		} else {
			$self->on_single_line($1);
		}
		return 1;
	}
	return 0;
}

=head2 configure

Apply callbacks and other parameters, preparing state for event loop start.

=cut

sub configure {
	my $self = shift;
	my %args = @_;

# Debug flag is used to control the copious amounts of data that we dump out when tracing
	if(exists $args{debug}) {
		$self->{debug} = delete $args{debug} ? 1 : 0;
	}

	# die "No host provided" unless $args{host} || $self->{transport};
	foreach (qw{host service user pass ssl tls}) {
		$self->{$_} = delete $args{$_} if exists $args{$_};
	}

# Don't think I like this much, but didn't want the list of callbacks held here
	%args = $self->Protocol::IMAP::Client::configure(%args);

	$self->SUPER::configure(%args);
	return $self;
}

sub on_user { shift->{user} }
sub on_pass { shift->{pass} }

=head2 on_connection_established

Prepare and activate a new transport.

=cut

sub on_connection_established {
	my $self = shift;
	my $sock = shift;
	my $transport = IO::Async::Stream->new(handle => $sock)
		or die "No transport?";
	$self->{transport} = $transport;
	$self->setup_transport($transport);
	my $loop = $self->get_loop or die "No IO::Async::Loop available";
	$loop->add($transport);
	$self->debug("Have transport " . $self->transport);
}

=head2 on_starttls

Upgrade the underlying stream to use TLS.

=cut

sub on_starttls {
	my $self = shift;
	$self->debug("Upgrading to TLS");

# Most of this taken directly from IO::Async::SSL, since we seem to be attempting to remove the transport from the list of children
# when doing the regular upgrade via ->configure(transport => undef) here. Could be something to do with the dodgy code in
# L<_add_to_loop>.
	require IO::Async::SSLStream;

	my $socket = $self->transport->read_handle;
	undef $self->{transport};

	$self->get_loop->SSL_upgrade(
		handle => $socket,
		on_upgraded => $self->_capture_weakself(sub {
			my ($self, $newsocket) = @_;
			$self->debug("TLS upgrade complete");

			my $sslstream = IO::Async::SSLStream->new(
				handle => $newsocket,
			);
			$self->{tls_enabled} = 1;

			$self->configure(transport => $sslstream);
			$self->get_capabilities;
		}),
		on_error => sub { die "error @_"; }
	);
}

=head2 start_idle_timer

=cut

sub start_idle_timer {
	my $self = shift;
	my %args = @_;

	$self->{idle_timer}->stop if $self->{idle_timer};
	$self->{idle_timer} = IO::Async::Timer::Countdown->new(
		delay => $args{idle_timeout} // 25 * 60,
		on_expire => $self->_capture_weakself( sub {
			my $self = shift;
			$self->done(
				on_ok => sub {
					$self->noop(
						on_ok => sub {
							$self->idle(%args);
						}
					);
				}
			);
		})
	);
	my $loop = $self->get_loop or die "Could not get loop";
	$loop->add($self->{idle_timer});
	$self->{idle_timer}->start;
	return $self;
}

=head2 stop_idle_timer

Disable the timer if it's running.

=cut

sub stop_idle_timer {
	my $self = shift;
	$self->{idle_timer}->stop if $self->{idle_timer};
}

=head2 _add_to_loop

Set up the connection automatically when we are added to the loop.

TODO: this is probably the wrong way to go about things, move this somewhere more appropriate.

=cut

sub _add_to_loop {
	my $self = shift;
	$self->SUPER::_add_to_loop(@_);
	my $loop = $self->get_loop or die "No IO::Async::Loop available";
	my $host = $self->{host};

	$self->state(Protocol::IMAP::ConnectionClosed);
	Scalar::Util::weaken(my $weakSelf = $self);
	$loop->connect(
		host		=> $self->{host},
		service		=> $self->{service} || 'imap2',
		socktype	=> SOCK_STREAM,
		on_resolve_error => sub {
			die "Resolution failed for $host";
		},
		on_connect_error => sub {
			die "Could not connect to $host";
		},
		on_connected => sub {
			my $sock = shift;
			$weakSelf->state(Protocol::IMAP::ConnectionEstablished, $sock);
		}
	);
	return $self;
}

1;
