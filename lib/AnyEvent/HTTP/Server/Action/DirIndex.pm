package AnyEvent::HTTP::Server::Action::DirIndex;

use uni::perl;
use URI;
use File::MimeInfo;
use File::Spec;
use POSIX 'strftime';

sub e($) {
	local $_ = shift;
	s{&}{&amp;}sg;
	s{<}{&lt;}sg;
	s{>}{&gt;}sg;
	s{"}{&quot;}sg; # "
	s{'}{&apos;}sg; # '
	$_;
}

sub sz($) {
	my $size = shift;
	my @sizes = qw( b K M G T);
	while ($size > 1024 and @sizes > 1) {
		$size /= 1024;
		shift @sizes;
	}
	return  sprintf +(int($size) == $size ? '%d%s' : '%0.1f%s'), $size, $sizes[0];
}

sub new {
	my $pk = shift;
	my $root = shift;
	return bless sub {
		my ( $r,$data ) = @_;
		if ($r->{method} eq 'GET') {
			my $uri = URI->new($r->{uri});
			my $rpath = $uri->path;
			my $path = $root.$rpath;
			my $canonical = File::Spec->canonpath( $rpath ) ;
			if (-d $path) {
				my $headers = HTTP::Easy::Headers->new({});
				$headers->{'content-type'} = 'text/html';
				#$headers->{'content-length'} = -s _;
				$headers->{'cache-control'} => 'no-cache, must-revalidate, max-age=0';
				my $body = sprintf q{<h1>Directory index for <code>%s</code></h1><table width="100%%" style="table-layout:fixed">}, e $canonical;
				opendir(my $d, $path);
				while (defined( $_ = readdir($d) )) {
					my $fx = $path.'/'.$_;
					$body .= '<tr>';
					my ($stat, $date);
					if (-f $fx) {
						my @stat = stat _;
						$stat = sz($stat[7]);
						$date = strftime("%Y-%m-%d %H:%M:%S",localtime($stat[9]));
					} else {
						
					}
					$body .= sprintf
						q{<tr><td width="80%%"><a href="%s">%s</a></td><td>%s</td><td>%s</td></tr>},
							e +File::Spec->canonpath( $rpath.'/'.$_ ),
							e $_.(-d $fx ? "/" : ''), 
							$stat,
							$date,
					;	
					#"$_<br>";
				}
				$body .= "</table>";
				if ($r->{method} eq 'HEAD') {
					$r->response(200, '', headers => $headers );
				} else {
					$r->response(200, $body, headers => $headers);
				}
				
			} else {
				return 0;
			}
		}
		else {
			return 0;
		}
	},$pk;
}

1;
