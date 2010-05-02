#!/usr/bin/env perl

use lib::abs '../lib';
use AnyEvent::HTTP::Server;
my $server = AnyEvent::HTTP::Server->new(request => sub {
	my $r = shift;
	warn "Request called";
	$r->response(200, "All is ok!\n");
});

$server->start;
AE::cv->recv;