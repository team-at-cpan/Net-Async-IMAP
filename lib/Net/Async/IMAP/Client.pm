package Net::Async::IMAP::Client;
use strict;
use warnings;
use parent qw(IO::Async::Stream);

use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use IO::Async::SSL;
use IO::Async::SSLStream;
use Protocol::IMAP::Client;
use curry;
use Future;
# IO::Async::Notifier

sub configure {
	my $self = shift;
	my %args = @_;
	$self->{debug} = delete $args{debug} if exists $args{debug};
	warn "debug was set: " . $self->{debug};
	$self->SUPER::configure(%args);
}

sub protocol {
	my $self = shift;
	unless($self->{protocol}) {
		$self->{protocol} = Protocol::IMAP::Client->new(
			debug => $self->is_debug,
			tls => 1,
		);
	}
	return $self->{protocol};
}

sub user { shift->{user} }
sub pass { shift->{pass} }
sub is_debug { shift->{debug} ? 1 : 0 }

sub on_read {
	my $self = shift;
	my ( $buffref, $closed ) = @_;
	1 while $self->protocol->on_read($buffref);
	return 0;
}

sub on_tls_upgraded {
	my $self = shift;
	my $sock = shift;
	warn "we have upgraded our SSLs to $sock\n";
	$self->protocol->{tls_enabled} = 1;
	my $stream = IO::Async::SSLStream->new(
		handle => $sock,
	);
	$stream->configure(
		on_read => sub { shift; $self->on_read(@_) },
	);
	$self->add_child($stream);
	$self->protocol->get_capabilities;
	$self
}

=head2 on_connected

Transformation to apply once the connection is established.

=cut

sub on_connected {
	my $self = shift;
	my $stream = shift;
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

sub authenticated { shift->{authenticated} ||= Future->new }

# proxy methods
sub status { $_[0]->protocol->status(@_[1..$#_]) }
sub select : method { $_[0]->protocol->select(@_[1..$#_]) }
sub fetch : method { $_[0]->protocol->fetch(@_[1..$#_]) }
sub list : method { $_[0]->protocol->list(@_[1..$#_]) }

1;

__END__

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2010-2013. Licensed under the same terms as Perl itself.

