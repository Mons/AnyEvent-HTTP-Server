package AnyEvent::HTTP::Server::Action::WS;

use uni::perl ':dumper';
use File::MimeInfo;

sub new {
	my $pk = shift;
	my $root = shift;
	return bless sub {
		my ( $r,$data ) = @_;
		if ($r->{method} eq 'GET' or $r->{method} eq 'HEAD' ) {
			my $uri = URI->new($r->{uri});
			my $rpath = $uri->path;
			my $path = $root.$rpath;
			warn "Return path $path";
			my @stat = stat $path;
			if (! -f _ and $rpath eq '/' and -f "$root/index.html") {
				$path = "$root/index.html";
				@stat = stat $path;
			}
			my $headers = HTTP::Easy::Headers->new({});
			if (-f _) {
				my $type = mimetype($path);
				warn "Defined type $type for $path";
				$headers->{'content-type'} = $type;
				$headers->{'content-length'} = -s _;
				$headers->{'cache-control'} => 'no-cache, must-revalidate, max-age=0';
				if ($r->{method} eq 'HEAD') {
					return $r->response(200,'', headers => $headers );
				} else {
					return $r->response(200,{sendfile => $path}, headers => $headers);
				}
			} else {
					warn "request $rpath";
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
						} else {
							$r->error(400)
						}
					} else {
						warn dumper $r->{headers};
						return $r->error(404);
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
