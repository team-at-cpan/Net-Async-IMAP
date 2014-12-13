use strict;
use warnings;

use Test::More;
use Net::Async::IMAP::Client;

{ # API behaviour
	can_ok('Net::Async::IMAP::Client', qw(
		status
		select
		fetch
		list
	));
}

{
	my $client = new_ok('Net::Async::IMAP::Client');
	isa_ok($client->protocol, 'Protocol::IMAP::Client');
}

done_testing;


