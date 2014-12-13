package Net::Async::IMAP::Client;

use strict;
use warnings;

use parent qw(IO::Async::Stream);

=head1 NAME

Net::Async::IMAP::Client - asynchronous IMAP client based on L<Protocol::IMAP::Client>

=head1 SYNOPSIS

 use IO::Async::Loop;
 use Net::Async::IMAP;
 my $loop = IO::Async::Loop->new;
 $loop->add(my $imap = Net::Async::IMAP::Client->new(
	host => 'mailserver.com',
	service => 'imap2',
	on_authenticated => sub {
		warn "login was successful";
		$loop->loop_stop;
	},
 ));
 $imap->login(
	user => 'user@mailserver.com',
	pass => 'password',
 );
 $loop->loop_forever;

=head1 DESCRIPTION

=head1 USAGE

First, instantiate the object and attach it to an L<IO::Async::Loop> instance:

 $loop->add(
  my $imap_client = Net::Async::IMAP::Client->new
 );

Next, request a connection to the server. This will resolve when the connection
is ready:

 $imap_client->connect(
  ...
 )->get;

Note that the IMAP connection has been established but we may not have completed
the authentication process yet. If you need to ensure that authentication is also
finished, use the L</authentication> method:

 $imap_client->authentication->get;

Normally this is not required - all IMAP requests made via methods in this module
will automatically wait for authentication.

=cut

use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use IO::Async::SSL;
use IO::Async::SSLStream;
use curry;
use Future;

use Protocol::IMAP::Client;
use Scalar::Util;

my $_curry_weak = sub {
	my ($invocant, $code) = splice @_, 0, 2;
	Scalar::Util::weaken($invocant) if Scalar::Util::blessed($invocant);
	my @args = @_;
	sub {
		return unless $invocant;
		$invocant->$code(@args => @_)
	}
};

=head1 METHODS

=head2 configure

=cut

#sub configure {
#	my $self = shift;
#	my %args = @_;
#	$self->{debug} = delete $args{debug} if exists $args{debug};
#	$self->SUPER::configure(%args);
#}

=head2 protocol

=cut

sub protocol {
	my $self = shift;
	unless($self->{protocol}) {
		$self->debug_printf('Instantiating new IMAP protocol object for client');
		$self->{protocol} = Protocol::IMAP::Client->new(
			debug => $self->curry::weak::debug_printf,
			tls   => 1,
		);
	}
	$self->{protocol}
}

=head2 user

=cut

sub user { shift->{user} }

=head2 pass

=cut

sub pass { shift->{pass} }

=head2 on_read

=cut

sub on_read {
	my ($self, $buffref, $closed) = @_;
	1 while $self->protocol->on_read($buffref);
	return 0;
}

=head2 on_tls_upgraded

=cut

sub on_tls_upgraded {
	my ($self, $sock) = @_;
	$self->debug_printf("TLS upgrade complete");
	$self->protocol->{tls_enabled} = 1;

	my $stream = IO::Async::SSLStream->new(
		handle => $sock,
	);
	$stream->configure(
		on_read => $self->$_curry_weak(sub {
			# Throw away $stream, we don't need it
			my ($self) = splice @_, 0, 2;
			$self->on_read(@_)
		}),
	);
	$self->add_child($stream);
	$self->protocol->get_capabilities;
	$self
}

=head2 on_connected

Transformation to apply once the connection is established.

=cut

sub on_connected {
	my ($self, $stream) = @_;
	$self->debug_printf('Connection established');
	$self->protocol->subscribe_to_event(
		write => sub {
			my ($ev, $data) = @_;
			$stream->write($data);
		},
		starttls => sub {
			my ($ev, $data) = @_;
			$self->loop->SSL_upgrade(
				handle => $self->read_handle,
				SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
			)->on_done(
				$self->curry::on_tls_upgraded
			)->on_fail(sub { warn "upgrade failed: @_" });
		},
		authentication_required => sub {
			my ($ev) = @_;
			$self->protocol->login(
				$self->user,
				$self->pass,
			);
		},
		authenticated => $self->authenticated->curry::done($self),
	);

	$self->protocol->state('ConnectionEstablished');
	$self
}

=head2 connect

=cut

sub connect {
	my $self = shift;
	my %args = @_;
	$self->{$_} = delete $args{$_} for grep exists $args{$_}, qw(user pass);

	$self->SUPER::connect(
		socktype => 'stream',
		# Although we support IMAP4bis, the IETF-assiged servicename is still 'imap2'
		service => 'imap2',
		%args
	)->transform(
		done => $self->curry::on_connected,
	);
}

=head2 authenticated

Returns a L<Future> which resolves once authentication
is complete.

=cut

sub authenticated {
	my ($self) = @_;
	$self->{authenticated} ||= $self->loop->new_future
}

=head1 PROXY METHODS

These methods are passed through to the underlying
L<Protocol::IMAP::Client> instance. See the documentation
there for further information.

=head2 status

L<Protocol::IMAP::Client/status>

=cut

sub status { $_[0]->protocol->status(@_[1..$#_]) }

=head2 select

L<Protocol::IMAP::Client/select>

=cut

sub select : method { $_[0]->protocol->select(@_[1..$#_]) }

=head2 fetch

L<Protocol::IMAP::Client/fetch>

=cut

sub fetch { $_[0]->protocol->fetch(@_[1..$#_]) }

=head2 list

L<Protocol::IMAP::Client/list>

=cut

sub list { $_[0]->protocol->list(@_[1..$#_]) }

1;

__END__

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2010-2014. Licensed under the same terms as Perl itself.

