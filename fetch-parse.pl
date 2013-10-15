#!/usr/bin/env perl 
use strict;
use warnings;
use 5.010;
#(
#	FLAGS (\Seen NonJunk)
#	INTERNALDATE "24-Feb-2012 17:41:19 +0000"
#	RFC822.SIZE 2144
#	ENVELOPE (
#		"Fri, 24 Feb 2012 12:41:15 -0500"
#		"[rt.cpan.org #72843] GET.pl example fails for reddit.com "
#		(("Paul Evans via RT" NIL "bug-Net-Async-HTTP" "rt.cpan.org"))
#		(("Paul Evans via RT" NIL "bug-Net-Async-HTTP" "rt.cpan.org"))
#		((NIL NIL "bug-Net-Async-HTTP" "rt.cpan.org"))
#		((NIL NIL "TEAM" "cpan.org"))
#		((NIL NIL "kiyoshi.aman" "gmail.com"))
#		NIL
#		""
#		"<rt-3.8.HEAD-10811-1330105275-884.72843-6-0@rt.cpan.org>"
#	)
#)
my $input = <<'EOF';
(FLAGS (\Seen NonJunk) INTERNALDATE "24-Feb-2012 17:41:19 +0000" RFC822.SIZE 2144 ENVELOPE ("Fri, 24 Feb 2012 12:41:15 -0500" "[rt.cpan.org #72843] GET.pl example fails for reddit.com " (("Paul Evans via RT" NIL "bug-Net-Async-HTTP" "rt.cpan.org")) (("Paul Evans via RT" NIL "bug-Net-Async-HTTP" "rt.cpan.org")) ((NIL NIL "bug-Net-Async-HTTP" "rt.cpan.org")) ((NIL NIL "TEAM" "cpan.org")) ((NIL NIL "kiyoshi.aman" "gmail.com")) NIL "" "<rt-3.8.HEAD-10811-1330105275-884.72843-6-0@rt.cpan.org>"))
EOF
#$input = '(FLAGS (\Seen NonJunk) INTERNALDATE "24-Feb-2012 17:41:19 +0000")';
use Protocol::IMAP::FetchResponseParser;
my $parser = Protocol::IMAP::FetchResponseParser->new;
use Data::Dumper; print Dumper($parser->from_string($input));

