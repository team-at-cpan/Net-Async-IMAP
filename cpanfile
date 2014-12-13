requires 'parent', 0;
requires 'Socket', 0;
requires 'curry', 0;
requires 'Protocol::IMAP', '>= 0.004';
requires 'IO::Async', '>= 0.63';
requires 'IO::Async::SSL', '>= 0.12';
requires 'IO::Socket::IP', 0;

on 'test' => sub {
	requires 'Test::More', '>= 0.98';
};

