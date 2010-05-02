package AnyEvent::HTTP::Server::Action::DAV;

use uni::perl;
use File::Copy;
use File::Copy::Recursive 'dircopy';
use AnyEvent::HTTP::Server::Action::Static;

sub new {
	my $pk = shift;
	my $root = shift;
	my $static = AnyEvent::HTTP::Server::Action::Static->new($root);
	return bless sub {
		my $r = shift;my $data = shift;
		if ($r->{method} eq 'MKCOL') {
			return $r->error(415) if length $data;
			return $r->error(409) if substr($r->{uri},-1,1) ne '/';
			my $path = $r->{uri}; substr($path,-1,1) = '';
			warn "Create path $root:$path";
			if( mkdir("$root/$path") ) {
				return $r->response( 201, 'Created', { 'Location' => '' }, '');
			} else {
				warn "$r->{method} $r->{uri} Conflict: $!";
				return $r->error(409);
			}
		}
		elsif ($r->{method} eq 'DELETE') {
			my $path = "$root/$r->{uri}";
			return $r->error(415) if length $data;
			if (stat $path) {
				if (-d _) {
					return $r->error(409) if substr($path,-1,1) ne '/';
					if( rmdir $path ) {
						return $r->response(204, 'No Content');
					} else {
						warn "rmdir $path failed: $!";
						return $r->error(404);
					}
				} else {
					if (unlink $path) {
						return $r->response(204, 'No Content');
					} else {
						warn "unlink $path failed: $!";
						return $r->error(404);
					}
				}
			} else {
				warn "Delete $path failed: $!";
				return $r->error($!{ENOTDIR} ? 409 : 404 );
			}
			
		}
		elsif ($r->{method} eq 'PUT') {
			my $path = "$root/$r->{uri}";
			my $status;
			if (-e $path) {
				$status = 204;
				if (-d _) {
					warn "File $path can't be created: is a directory";
					return $r->error(409);
				}
			} else {
				$status = 201;
			}
			if (open my $f, '>', $path) {
				print $f $data;
				close $f;
				my $h = {};
				if ($status == 201) {
					$h->{Location} = '...';
				}
				return $r->response($status);
			} else {
				warn "Can't open file $path: $!";
				return $r->error(500);
			}
		}
		elsif ($r->{method} eq 'COPY' or $r->{method} eq 'MOVE' ) {
			my $src = "$root$r->{uri}";
			return $r->error(415) if length $data;
			my $dest = $r->{headers}{Destination};
			my $host = $r->{headers}{Host};
			return $r->error(400) unless $dest and $host;
			return $r->error(400) unless $dest =~ s{^https?://\Q$host\E/}{/};
			my $dst = "$root$dest";
			warn "Dest = $dest => $dst";
			my $src_col = substr($src,-1,1) eq '/';
			my $dst_col = substr($dst,-1,1) eq '/';
			if ($dst_col xor $src_col) {
				warn "$src => $dst should be either collections or non-collections";
				return $r->error(409);
			}
			my $overwrite = 1;
			if( my $over = $r->{headers}{Overwrite} ) {
				if ($over =~ /^t/i) {
					$overwrite = 1;
				}
				elsif ($over =~ /^f/i) {
					$overwrite = 0;
				}
				else {
					return $r->error(400);
				}
			}
			my $dir;
			if (!-e $dst) {
				$overwrite = 0;
				$dir = 0;
			} else {
				$dir = ( -d _ ) ? 1 : 0;
				if ($dir and !$dst_col) {
					warn sprintf "%s could not be %sed to collection %s", $src, $r->{method},$dst;
					return $r->error(400);
				}
				if (!$overwrite) {
					warn sprintf "%s could not be created", $dst;
					return $r->error(412);
				}
			}
			return $r->error(404) unless -e $src;
			
			if (-d _) {
				return $r->error(400) unless $src_col;
				if ($overwrite) {
					return $r->error(500) unless rmdir $dst;
				}
				if ($r->{method} eq 'MOVE') {
					if(rename $src,$dst) {
						return $r->response(201, 'Created');
					} else {
						warn "rename $src => $dst failed: $!";
						return $r->error(500);
					}
				}
				else { # COPY
					if (dircopy $src,$dst) {
						return $r->response(201, 'Created');
					} else {
						warn "dircopy $src => $dst failed: $!";
						return $r->error(500);
					}
				}
			} else {
				if ($r->{method} eq 'MOVE') {
					if(rename $src,$dst) {
						return $r->response(204, 'No Content');
					} else {
						warn "rename $src => $dst failed: $!";
						return $r->error(500);
					}
				}
				else { # COPY
					if (copy $src,$dst) {
						return $r->response(204, 'No Content');
					} else {
						warn "copy $src => $dst failed: $!";
						return $r->error(500);
					}
				}
			}
			
		}
		elsif($r->{method} eq 'GET' or $r->{method} eq 'HEAD') {
			return $static->($r,$data);
		}
		else {
			$r->error(405);
			#$r->response(405,"Not ", {}, "Yep, it works\n");	
		}
		#warn "$r->{method} $r->{host} $r->{uri}";
		#$r->response(200,"OK", {}, "Yep, it works\n");
		#$r->response(200,"OK", {}, { sendfile => __FILE__ });
	}, $pk;

}

1;
