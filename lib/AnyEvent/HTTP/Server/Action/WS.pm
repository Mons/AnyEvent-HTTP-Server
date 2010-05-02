package AnyEvent::HTTP::Server::Action::WS;

use uni::perl ':dumper';

sub new {
	my $pk = shift;
	my $root = shift;
	return bless sub {
		my ( $r,$data ) = @_;
		if ($r->{method} eq 'GET' or $r->{method} eq 'HEAD' ) {
			my $path = "$root$r->{uri}";
			warn "Return path $path";
			my @stat = stat $path;
			my $type =
				$path =~ /\.html$/ ? 'text/html' :
				$path =~ /\.js$/ ? 'text/javascript' :
				'application/octet-stream';
			if (-f _) {
				if ($r->{method} eq 'HEAD') {
					return $r->response(200,"OK",{ 'Content-Length', -s _ },'');
				} else {
					return $r->response(200,"OK",{ 'Content-Type' => $type, 'cache-control' => 'no-cache, must-revalidate, max-age=0' },{sendfile => $path});
				}
			} else {
				if ($r->{uri} eq '/' and -e "$root/index.html") {
					return $r->response(200,"OK",{},{sendfile => "$root/index.html"});
				} else {
					warn "$r->{uri}";
					if ($r->wants_websocket) {
						warn "Request $r->{uri} wants websocket upgrade!";
						$r->upgrade('websocket', {}, sub {
							if (my $ws = shift) {
								$ws->onmessage(sub {
									warn "Got message: @_";
									$ws->send("re: @_");
								});
							} else {
								warn "Upgrade failed: @_";
							}
						});
					} else {
						warn dumper $r->{headers};
						return $r->error(404);
					}
				}
			}
		}
		else {
			$r->error(405);
			#$r->response(405,"Not ", {}, "Yep, it works\n");	
		}
	},$pk;
}

1;
