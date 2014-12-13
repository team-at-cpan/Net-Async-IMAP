package Net::Async::IMAP::Client;

use strict;
use warnings;

use parent qw(IO::Async::Stream);

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
		service => 'imap2',
		%args
	)->transform(
		done => $self->curry::on_connected,
	);
}

=head2 authenticated

=cut

sub authenticated {
	my ($self) = @_;
	$self->{authenticated} ||= $self->loop->new_future
}

# proxy methods

=head2 status

=cut

sub status { $_[0]->protocol->status(@_[1..$#_]) }

=head2 select

=cut

sub select : method { $_[0]->protocol->select(@_[1..$#_]) }

=head2 fetch

=cut

sub fetch { $_[0]->protocol->fetch(@_[1..$#_]) }

=head2 list

=cut

sub list { $_[0]->protocol->list(@_[1..$#_]) }

1;

__END__

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2010-2014. Licensed under the same terms as Perl itself.

