#!/usr/bin/perl 
use strict;
use warnings;

use IO::Async::Loop;
use IO::Async::Timer::Countdown;
use Net::Async::IMAP::Client;

# Use one of the Perl Email Project modules for handling the email parsing. This one's good enough for our needs.
use Email::Simple;

# Standard event loop creation
my $loop = IO::Async::Loop->new;

# Maintain current message state
my $total;
my $cur = 1;

# We create a new client instance, passing the information needed to connect - when the event loop starts, this
# should make the connection for us and call the on_authenticated callback.
my $imap = Net::Async::IMAP::Client->new(
	# Set the debug flag to 1 to see lots of tedious detail about what's happening.
	debug			=> 0,
	host			=> $ENV{NET_ASYNC_IMAP_SERVER},
	service			=> $ENV{NET_ASYNC_IMAP_PORT} || 'imap',
	user			=> $ENV{NET_ASYNC_IMAP_USER},
	pass			=> $ENV{NET_ASYNC_IMAP_PASS},
	on_authenticated	=> \&check_server,
);

$loop->add($imap);

$loop->loop_forever;

# First task is to check the status for the mailbox
sub check_server {
	$imap->status(
		on_ok => sub {
			my $data = shift;
# Store the total number of messages and report what we found
			$total = $data->{messages};
			warn "Message count: " . $data->{messages} . ", next: " . $data->{uidnext} . "\n";
# Then pass on to the next task in the list - you should probably weaken a copy of $imap here
			$imap->select(
				mailbox => 'INBOX',
				on_ok => sub {
					return unless $cur <= $total;
					fetch_message(++$cur);
				}
			);
		}
	);
}

sub fetch_message {
	my $idx = shift;
	$imap->fetch(
# Provide the ID for the message to fetch here - one-based, not zero-based!
		message => $idx,

# Specify which parts of the message you want - if you only need subject/from/to etc., then just ask for the headers
		type => 'RFC822.HEADER',
		# type => 'RFC822.HEADER RFC822.TEXT',
		on_ok => sub {
			my $msg = shift;

			my $es = Email::Simple->new($msg);
			my $hdr = $es->header_obj;
			printf("[%03d] %s\n", $idx, $es->header('Subject'));
			printf(" - %s\n", join(',', $hdr->header_names));
			if($cur < $total) {
				fetch_message(++$cur);
			} else {
				$loop->loop_stop;
			}
		}
	);
}
