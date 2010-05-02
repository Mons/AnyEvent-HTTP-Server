package AnyEvent::HTTP::Server::Action::PP;

use uni::perl ':dumper';
use AnyEvent::HTTP;

sub new {
	my $pk = shift;
	my %args = @_;
	return bless sub {
		my ( $r,$data ) = @_;
		if ($r->{method}) {
			http_request
				$r->{method},
				$args{pass} . $r->{uri},
				timeout => $args{timeout} || 60,
				headers => $args{headers} ? ({
					%{$r->{headers}},
					%{$args{headers}},
				} ) : $r->{headers},
				sub {
					my ($code,$msg) = delete @{$_[1]}{qw(Status Reason URI HTTPVersion)};
					warn "Response ".dumper $_[1];
					$r->response($code,$msg, $_[1], $_[0]);
				};
		}
		else {
			$r->error(405);
			#$r->response(405,"Not ", {}, "Yep, it works\n");	
		}
	},$pk;
}

1;
