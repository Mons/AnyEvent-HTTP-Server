#!/usr/bin/env perl

use lib::abs '../lib';
use AnyEvent::HTTP::Server;
my $server = AnyEvent::HTTP::Server->new();

$server->start;
AE::cv->recv;