package AnyEvent::HTTP::Server::Action::Static;

use uni::perl;
use URI;
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
			#warn "Return path $path";
			my @stat = stat $path;
			if (! -f _ and $rpath eq '/' and -f "$root/index.html") {
				$path = "$root/index.html";
				@stat = stat $path;
			}
			my $headers = HTTP::Easy::Headers->new({});
			if (-f _) {
				my $type = mimetype($path);
				#warn "Defined type $type for $path, size=". -s _;
				$headers->{'content-type'} = $type;
				$headers->{'content-length'} = -s _;
				$headers->{'cache-control'} => 'no-cache, must-revalidate, max-age=0';
				if ($r->{method} eq 'HEAD') {
					$r->response(200, '', headers => $headers );
				} else {
					$r->response(200, {sendfile => $path}, headers => $headers);
				}
				return 1;
			} else {
				warn "File `$path' not found";
				return 0;
			}
		}
		else {
			return 0;
		}
	},$pk;
}

1;
