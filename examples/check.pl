#!/usr/bin/perl 
use strict;
use warnings;

use IO::Async::Loop;
use IO::Async::Timer::Countdown;
use Net::Async::IMAP::Client;

use Email::Simple;

my $loop = IO::Async::Loop->new;
my $imap = Net::Async::IMAP::Client->new(
	debug			=> 1,
	host			=> $ENV{NET_ASYNC_IMAP_SERVER},
	service			=> $ENV{NET_ASYNC_IMAP_PORT} || 'imap',
	user			=> $ENV{NET_ASYNC_IMAP_USER},
	pass			=> $ENV{NET_ASYNC_IMAP_PASS},
	on_authenticated	=> sub {
		checkServer();
	},
);

my $total;
sub checkServer {
	$imap->status(
		on_ok => sub {
			my $data = shift;
			$total = $data->{messages};
			warn "Message count: " . $data->{messages} . ", next: " . $data->{uidnext} . "\n";
			selectMailbox();
		}
	);
}

my $cur = 1;
sub selectMailbox {
	$imap->select(
		mbox => 'INBOX',
		on_ok => sub {
			fetchNewMessage(3);
		}
	);
}

sub fetchNewMessage {
	my $idx = shift;
	$imap->fetch(
		message => $idx,
		type => 'RFC822.TEXT',
		on_ok => sub {
			my $msg = shift;
#			print $msg;
			my $es = Email::Simple->new($msg);
			warn sprintf("[%03d] %s\n", $idx, $es->header('Subject'));
			$loop->loop_stop;
		}
	);
}

$loop->add($imap);
$loop->loop_forever;

