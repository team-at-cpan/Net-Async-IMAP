package Net::Async::IMAP::Client;
# ABSTRACT: Asynchronous IMAP client
use strict;
use warnings;
use parent qw{IO::Async::Protocol::Stream Protocol::IMAP::Client};

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
	on_authenticated => sub {
		warn "login was successful";
		$loop->loop_stop;
	},
 );
 $loop->loop_forever;

=head1 DESCRIPTION

=head1 METHODS

=cut

1;
