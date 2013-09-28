#!/usr/bin/env perl 
use strict;
use warnings;
use 5.010;
package Net::Async::IMAP::Client;
use parent qw(IO::Async::Stream);
use IO::Socket::SSL qw(SSL_VERIFY_NONE);
use IO::Async::SSL;
use IO::Async::SSLStream;
use Protocol::IMAP::Client;
use curry;
use Future;
# IO::Async::Notifier

sub _init {
	my $self = shift;
	$self->{protocol} = Protocol::IMAP::Client->new(
		debug => 0,
		tls => 1,
	);
	$self->SUPER::_init(@_)
}

sub protocol { shift->{protocol} }
sub user { shift->{user} }
sub pass { shift->{pass} }

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

package main;
use IO::Async::Loop;
use Email::Simple;
use Try::Tiny;
use Future::Utils;
use Date::Parse qw(str2time);
use POSIX qw(strftime);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

my $loop = IO::Async::Loop->new;
my $imap = Net::Async::IMAP::Client->new;
$loop->add($imap);
$imap->connect(
	user     => 'tom@audioboundary.com',
	pass     => 'd3m0n1c',
	host     => 'audioboundary.com',
	service  => 'imap2',
#	user     => 'trendeu\\tom_molesworth',
#	pass     => 'PhuSee2v',
#	host     => 'localhost',
#	service  => '9143',
	socktype => 'stream',
)->on_done(sub {
	my $imap = shift;
	warn "Connection established\n";
#	$loop->SSL_upgrade(
#		handle => $imap->read_handle,
#	)->on_done(sub { warn "upgraded!" })->on_fail(sub { warn "failed: @_" });
})->on_fail(sub {
	warn "Failed to connect: @_\n"
});
my $idx = 3940;
my $f = $imap->authenticated->then(sub {
	warn "Authentication seems to have finished";
	$imap->status
})->then(sub {
	warn "Status ready:\n";
	my $status = shift;
	$imap->list(
	)
})->then(sub {
#	use Data::Dumper; warn Dumper($status);
	$imap->select(
		mailbox => 'INBOX'
	);
})->then(sub {
	warn "Select complete: @_";
	my $status = shift;
	use Data::Dumper; warn Dumper($status);
#	Future::Utils::repeat {
	my $total = 0;
	my $max = $status->{messages} // 27;
		$imap->fetch(
			message => $idx . ":" . $max,
#			message => "1,2,3,4",
			# type => 'RFC822.HEADER',
			# type => 'BODY',
			# type => 'BODY[]',
			type => 'ALL',
#			type => '(FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODY[])',
			on_fetch => sub {
				my $msg = shift;

				try {
					my $size = $msg->data('size')->get;
					$msg->data('envelope')->on_done(sub {
						my $envelope = shift;
						my $date = strftime '%Y-%m-%d %H:%M:%S', localtime str2time($envelope->date);
						printf "%4d %-20.20s %8d %-64.64s\n", $idx, $date, $size, Encode::decode('IMAP-UTF-7' => $envelope->subject);
	#					say "Message ID: " . $envelope->message_id;
	#					say "Subject:    " . $envelope->subject;
	#					say "Date:       " . $envelope->date;
	#					say "From:       " . join ',', $envelope->from;
	#					say "To:         " . join ',', $envelope->to;
	#					say "CC:         " . join ',', $envelope->cc;
	#					say "BCC:        " . join ',', $envelope->bcc;
					});
					$total += $size;
				} catch { warn "failed: $_" };
				++$idx;
			}
		)->on_fail(sub { warn "failed fetch - @_" })->on_done(sub {
			printf "Total size: %d\n", $total;
		});
#	} while => sub { ++$idx < $status->{messages} };
#	my $es = Email::Simple->new($msg);
#	my $hdr = $es->header_obj;
#	printf("[%03d] %s\n", $idx, $es->header('Subject'));
#	printf(" - %s\n", join(',', $hdr->header_names));
})->on_fail(sub { die "Failed - @_" })->on_done(sub { $loop->stop });
$loop->later(sub { DB::enable_profile() }) if $INC{'Devel/NYTProf.pm'};
$loop->run;
DB::disable_profile() if $INC{'Devel/NYTProf.pm'};

