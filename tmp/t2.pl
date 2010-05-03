#!/usr/bin/env perl

use lib::abs '../lib';
use lib::abs '../../AnyEvent-Handle-Writer/lib';
use uni::perl ':dumper';
use AnyEvent::HTTP::Server;
use File::MimeInfo;
use AnyEvent::HTTP::Server::Action::WS;
use AnyEvent::HTTP::Server::Action::Chain;
use AnyEvent::HTTP::Server::Action::Static;
#$AnyEvent::Handle::Writer::NO_SENDFILE = 1;
my $server = AnyEvent::HTTP::Server->new(
	host => '89.208.136.108',
	port => 80,
	#request => AnyEvent::HTTP::Server::Action::WS->new(lib::abs::path('root')),
	request => AnyEvent::HTTP::Server::Action::Chain->new(
		root => 	lib::abs::path('root'),
		chain => [
			sub {
				my $r = shift;
				my $rpath = $r->{uri}->path;
					if ($r->wants_websocket) {
						warn "Request $r->{uri} wants websocket upgrade!";
						if ($rpath =~ m{^/ws/?}) {
							$r->upgrade('websocket', sub {
								if (my $ws = shift) {
									$ws->onmessage(sub {
										warn "Got message: @_";
										$ws->send("re: @_");
									});
								} else {
									warn "Upgrade failed: @_";
								}
							});
							return 1;
						}
						elsif ( $rpath =~ m{^/echo/?$}) {
							$r->upgrade('websocket', sub {
								if (my $ws = shift) {
									$ws->onmessage(sub {
										$ws->send("@_");
									});
								} else {
									warn "Upgrade failed: @_";
								}
							});
							return 1;
						} else {
							$r->error(400);
							return 1;
						}
					} else {
						return 0;
					}
			},
			AnyEvent::HTTP::Server::Action::Static->new(lib::abs::path('root')),
		],
	),
	policy_request => sub {
		warn "Handle policy request\n";
		shift->(
			'site-control' => { 'permitted-cross-domain-policies' => 'master-only' },
			'allow-access-from' => { 'domain' => "*.xfo.cc", 'to-ports' => "80" },
		);
	},
	1 => sub {
		my $r = shift;
		warn "Request called";
		$r->response(200, "All is ok!\n");
	}
);

$server->start;
my $cv = AE::cv;
$SIG{INT} = sub { $cv->send; };
$cv->recv;