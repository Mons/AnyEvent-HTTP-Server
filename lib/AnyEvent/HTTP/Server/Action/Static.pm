package AnyEvent::HTTP::Server::Action::Static;

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
			if (-f _) {
				if ($r->{method} eq 'HEAD') {
					return $r->response(200,"OK",{ 'Content-Length', -s _ },'');
				} else {
					return $r->response(200,"OK",{},{sendfile => $path});
				}
			} else {
				if ($r->{uri} eq '/' and -e "$root/index.html") {
					return $r->response(200,"OK",{},{sendfile => "$root/index.html"});
				} else {
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
