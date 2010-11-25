#!/usr/bin/env perl

use uni::perl;
use lib::abs '../../lib';
use AnyEvent::Impl::Perl; # Better to use Impl::Perl for tests
use AE;
use AnyEvent::HTTP::Server;

AnyEvent::HTTP::Server->new(
	host    => '89.208.136.108',
	port    => 8088,
	pid     => '/tmp/wsecho.pid',
	request => sub {
		my $r = shift;
		my $rpath = $r->{uri}->path;
		warn "Request $rpath";
		if ($r->wants_websocket) {
			$r->upgrade('websocket', sub {     # Respond with upgrade
				if (my $ws = shift) {          # Receive websocket object
					$ws->onmessage(sub {       # Setup WebSocket on_message
						$ws->send("re: @_");
					});
					$ws->send("Hello from sample!");       # Send initial "Hello!" from server
				} else {
					warn "Upgrade failed: @_";
				}
			});
			return 1;
		} else {
			$r->error(400);
			return 1;
		}
	},
)->start;

AE::cv->recv; # Start loop
