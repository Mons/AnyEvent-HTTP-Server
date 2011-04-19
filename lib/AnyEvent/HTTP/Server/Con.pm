package AnyEvent::HTTP::Server::Con::destroyed;

use overload
	'bool' => sub {0},
	fallback => 1;

sub AUTOLOAD {}
sub DESTROY {} # my $self = shift; warn "Really destroy $self->{id} $self->{host}:$self->{port}\n"; }

package AnyEvent::HTTP::Server::Con;

use common::sense;
use AE 5;
use AnyEvent::Handle::Writer;
use Scalar::Util qw(weaken);
use HTTP::Easy::Headers;
use HTTP::Easy::Status;

sub log:method {
	my $self = shift;
	my $fmt = shift;
	$fmt =~ s{\n+$}{};
	warn
		sprintf
		#"[@{[ ~~localtime ]}] - ".
		"$self->{id} | %-15s - $fmt\n",$self->{host}, @_;
}



sub new {
	my $self = bless {}, shift;
	weaken (my $this = $self);
	my %args = @_;
	my $srv = $args{server};
	my $fh  = $args{fh};
	my $h = AnyEvent::Handle::Writer->new(
	#my $h = AnyEvent::Handle->new(
		fh         => $fh,
		on_eof     => sub { $this or return; $this->error("EOF from client") },
		on_error   => sub { $this or return; $this->error("$!") },
	);
	weaken($self->{srv} = $srv);
	$self->{id} = int $self;
	$self->{fh} = $fh;
	$self->{h}  = $h;
	$self->{r}  = [],
	$self->{host} = $args{host};
	$self->{port} = $args{port};
	$self->{ka_timeout} = $srv->{keep_alive_timeout} || 30;
	if ($srv->{keep_alive}) {
		$self->{touch} = AE::now;
		$self->ka_timer;
	}
	$self->{state} = 'idle';
	$self->read_header();
	return $self;
}


sub ka_timer {
	my $self = shift;
	$self->{srv} or return $self->destroy;
	weaken (my $this = $self);
	$self->{ka} = AE::timer $this->{ka_timeout} + 1, 0, sub {
		$this or return;
		warn "closing by timeout keep-alive connection from $this->{host}:$this->{port}\n";
		if (AE::now - $this->{touch} >= $this->{ka_timeout}) {
			$this->close;
		} else {
			$this->ka_timer;
		}
	}
}

sub read_header {
	my $self = shift;
	$self->{srv} or return $self->destroy;
	$self->{state} = 'idle';
	weaken (my $con = $self);
	#warn "Begin reading from connection";
	$con->{h}->push_read(chunk => 3 => sub {
		$con or return;shift;
		$self->{state} = 'headers';
		my $pre = shift;
		if ($pre =~ m{^<}) {
			$con->{h}->unshift_read(regex => qr{.+?>} => sub {
				$con or return;shift;
				my $line = shift;
				my $xml = $pre.$line;
				warn "XML Request $xml";
				if ($xml =~ m{^\s*<policy-file-request\s*/>\s*$} and $con->{srv}{policy_request}) {
					$con->{srv}{policy_request}->(sub {
						my $res;
						if (@_ == 1 and !ref $_[0]) {
							$res = shift;
						} else {
						my %args = @_;
						$res = '<?xml version="1.0" encoding="utf-8"?><cross-domain-policy>';
						while (my ($node,$value) = each %args) {
							$node =~ s{[^a-z0-9-]}{}sgo;
							$res .= '<'.$node;
							while (my ($k,$v) = each %$value) {
								$k =~ s{[^a-z0-9-]}{}sg;
								for ($v) {
									s{&}{&amp;}sgo;
									s{<}{&lt;}sgo;
									s{>}{&gt;}sgo;
									s{"}{&quot;}sgo; #"
								}
								$res .= qq{ $k="$v"};
							}
							$res .= ' />';
						}
						$res .= '</cross-domain-policy>';
						}
						$con->{h}->push_write($res."\0");
					});
				}
				elsif ($con->{srv}{xml_request}) {
					$con->{srv}{xml_request}->($xml,$con);
					return;
				}
				else {
					warn "Not handled XML $pre$line";
				}
				$con->destroy();
			});
		} else {
			$con->{h}->unshift_read(line => sub {
				$con or return;shift;
				my $line = $pre.shift;
				#warn "$con->{id}: $line";
				if ($line =~ /(\S+) \040 (\S+) \040 HTTP\/(\d+\.\d+)/xso) {
					my ($meth, $url, $hv) = ($1, $2, $3);
					$con->{method} = $meth;
					$con->{uri} = $url;
					$con->{version} = $hv;
					$con->read_headers();
				}
				elsif ($line eq '') {
					$con->read_header();
				}
				else {
					$con->fatal_error(400);
				}
			});
		};
	});
}

sub read_headers {
	my ($self) = @_;
	$self->{srv} or return $self->destroy;
	weaken (my $con = $self);
	$con->{h}->unshift_read (
		line => qr{(?<![^\012])\015?\012}o,
		sub {
			$con or return;
			my ($h, $data) = @_;
			my $hdr = HTTP::Easy::Headers->decode($data);
			unless (defined $hdr) {
				$con->fatal_error(400);
				return;
			}
			#warn dumper $hdr;
			my $r = $con->{srv}{request_class}->new(
				method  => delete $con->{method},
				uri     => delete $con->{uri},
				host    => $hdr->{Host},
				headers => $hdr,
			);
			$hdr->{connection} = lc $hdr->{connection};
			push @{ $con->{r} }, $r;
			weaken($r->{con} = $con);
			weaken($con->{r}[-1]);
			if ($hdr->{connection} eq 'close' or $con->{version} < 1.1) {
				$con->{close} = 1;
				delete $con->{ka};
				$con->{type} = 'close';
			}
			elsif ($hdr->{connection} =~ /keep-alive/) {
				$con->{close} = 0;
				$con->{type} = 'keep-alive';
			}
			elsif ($hdr->{connection} eq 'upgrade') {
				delete $con->{ka};
				$con->{type} = 'upgrade';
				$con->{close} = 0;
			}
			if (defined $hdr->{'content-length'}) {
				#warn "reading content $hdr->{'content-length'}";
				$con->{h}->unshift_read (chunk => $hdr->{'content-length'}, sub {
					my ($hdl, $data) = @_;
					$con->handle_request($r, $data);
					$con->read_header() if $con->{ka};
				});
			} else {
				$con->handle_request($r);
				$con->read_header() if $con->{ka};
			}
		}
	);
}

sub handle_request {
	my $self = shift;
	$self->{srv} or return $self->destroy;
	local $@;eval{
		$self->{srv}->handle_request(@_);
	1} or warn;
}

our @HEADER_ORDER = qw(upgrade connection websocket-origin websocket-location sec-websocket-origin sec-websocket-location);
our @HEADER_NAME  = qw(Upgrade Connection WebSocket-Origin WebSocket-Location Sec-WebSocket-Origin Sec-Websocket-Location);
our %HEADER_NAME;@HEADER_NAME{@HEADER_ORDER} = @HEADER_NAME;

# response ("Text")
# response (200, "Text")
# response (200, "Text", headers => {  })

sub response {
	my ($con,$r,$code,$content, %args) = @_;
	my $msg = $args{msg} || $HTTP::Easy::Status::MSG{$code} || "Code-$code";
	my $hdr = exists $args{headers} ? do {
		my %h;
		while (my ($h, $v) = each %{ $args{headers} }) {
			next unless defined $v;
			$h{lc $h} = $v;
		}
		\%h;
	} : HTTP::Easy::Headers->new({});
	
	# Resolve pipeline
	if (@{$con->{r}} and $con->{r}[0] == $r) {
		shift @{ $con->{r} };
	} else {
		$r->{ready} = [ $code, $msg, $hdr, $content ];
		return;
	}
	my $res = "HTTP/$con->{version} $code $msg\015\012";
	$hdr->{'content-type'} ||= 'text/html';
	if (ref $content eq 'HASH') {
		if ($content->{sendfile}) {
			$content->{size} = 
			$hdr->{'content-length'} = -s $content->{sendfile};
		}
	}
	#$hdr->{'expires'}        = $hdr->{'Date'}
	#                         = _time_to_http_date time;
	#$hdr->{'cache-control'}  = "max-age=0";
	if (!ref $content and length $content ) {
		#utf8::decode $content;
		utf8::encode $content if utf8::is_utf8($content);
	}
	$hdr->{connection} ||= $con->{type};
	if ($code >= 400 and !length $content ) {
		$content = <<EOC;
<html>
<head><title>$code $msg</title></head>
<body bgcolor="white">
<center><h1>$code $msg</h1></center>
<hr><center>AnyEvent::HTTP::Server/$AnyEvent::HTTP::Server::VERSION</center>
</body>
</html>
EOC
	}

	$hdr->{'content-length'} = length $content
		if not (defined $hdr->{'content-length'})
		and not ref $content
		and $code !~ /^(?:1\d\d|[23]04)$/;

	#unless (defined $hdr->{'content-length'}) {
		# keep alive with no content length will NOT work.
		# TODO: chunked
		# delete $self->{keep_alive};
	#}
	for (@HEADER_ORDER) {
		if (my $v = delete $hdr->{$_}) {
			$res .= "$HEADER_NAME{$_}: $v\015\012";
		}
	}
	while (my ($h, $v) = each %$hdr) {
		next unless defined $v;
		if (lc $h eq 'content-type' and $v !~ /charset/) {
			$v .= '; charset=utf-8';
		}
		$res .= "\u$h: $v\015\012";
	}

	$res .= "\015\012";
	warn "<$res>";
	$con->{h}->push_write($res);
	$con->log("%s - %s",$code,$r->{uri});
	#warn "Respond to $con->{id}:\n$res";

=for rem
	if (ref ($content) eq 'CODE') {
		weaken $self;
	
		my $chunk_cb = sub {
			my ($chunk) = @_;
	
			return 0 unless defined ($self) && defined ($self->{hdl});
	
			delete $self->{transport_polled};
	
			if (defined ($chunk) && length ($chunk) > 0) {
				$self->{hdl}->push_write ($chunk);
	
			} else {
				$self->response_done;
			}
	
			return 1;
		};
	
		$self->{transfer_cb} = $content;
	
		$self->{hdl}->on_drain (sub {
			return unless $self;
	
			if (length $res) {
				my $r = $res;
				undef $res;
				$chunk_cb->($r);
	
			} elsif (not $self->{transport_polled}) {
				$self->{transport_polled} = 1;
				$self->{transfer_cb}->($chunk_cb) if $self;
			}
		});
	
	}
	else {
=cut
		$res .= $content unless ref $content;
		#warn "Send response $code on $r->{method} $r->{uri}";
		if (ref $content eq 'HASH') {
			if ($content->{sendfile}) {
				$con->{h}->push_sendfile($content->{sendfile}, $content->{size});
			}
		} else {
			if (length $content) {
				#utf8::decode $content;
				#utf8::encode $content if utf8::is_utf8($content);
				$con->{h}->push_write($content);
			};
		}
	#}
	if ($con->{close}) {
		$con->close();
	} else {
		if ( @{$con->{r}} and $con->{r}[0]{ready}) {
			$con->response($con->{r}[0],@{$con->{r}[0]{ready}});
		}
	}
}

# error (500)
# error (500, "Text")
# error (200, "Text", headers => {  })

sub error {
	my ($self, $msg) = @_;
	warn "Error $msg";
	if ( @{$self->{r}} ) {
		$self->response( $self->{r}[0], 500, $msg );
	} else {
		warn "Have no pending requests";
	}
	$self->{on_error} and $self->{on_error}->($msg);
	$self->destroy;
}

sub destroy {
	my ($self) = @_;
	$self->DESTROY;
	bless $self, "AnyEvent::HTTP::Server::Con::destroyed";
}

sub DESTROY {
	my $self = shift;
	#warn "closing connection $self->{id}. $self / $self->{srv}{con}{ $self->{id} }\n";
	$self->{srv} and delete $self->{srv}{con}{ $self->{id} };
	$self->{state} = 'idle';
	my $x = $self->{close};
	$self->{h} and $self->{h}->destroy();
	%$self = ( state => 'closed', id => $self->{id}, host => $self->{host}, port => $self->{port} );
	ref $x and $x->(),undef $x;
	return;
}

sub close {
	my $self = shift;
	$self->destroy;
	return;
}

1;
