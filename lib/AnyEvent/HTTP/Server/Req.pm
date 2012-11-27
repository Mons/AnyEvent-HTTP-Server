package AnyEvent::HTTP::Server::Req;

use common::sense;
use HTTP::Easy::Status;
use HTTP::Easy::Headers;
use Digest::SHA1 'sha1';
use MIME::Base64 'decode_base64','encode_base64';
use URI;

sub new {
	my $pk = shift;
	my $self = bless {@_},$pk;
	$self->{uri} = URI->new($self->{uri});
	$self;
}

sub uri { $_[0]{uri} }

sub wants_websocket {
	my $self = shift;
	return lc $self->{headers}{connection} =~ /upgrade/ && lc $self->{headers}{upgrade} eq 'websocket' ? 1 : 0;
}

sub upgrade {
	my $self = shift;
	my $cb = pop;
	my $type = shift;
	my $headers = shift || HTTP::Easy::Headers->new({});
	if (lc $type eq 'websocket') {
		my $subtype = shift;
		$headers->{upgrade}    = 'WebSocket';
		$headers->{connection} = 'Upgrade';
		if (exists $self->{headers}{'sec-websocket-key1'}) {
			$self->{con}->access_log( ws => 1, m => "WebSocket Protocol 76" );
			#warn "WebSocket Protocol 76 request\n";
			$self->{con}{h}->push_read(chunk => 8, sub {
				shift;
				my $key3 = shift;
				my @keys;
				for (qw( sec-websocket-key1 sec-websocket-key2)) {
					my $key = $self->{headers}{$_};
					my $sp = $key =~ s/ //g;
					if ($sp == 0) { warn "Key $_ have no spaces"; return $self->error(400); $cb->undef("Bad $_"); }
					$key =~ s/\D+//g;
					warn "key extract = $key / $sp";
					$key = int ($key / $sp);
					$key = pack N => $key;
					push @keys, $key;
				}
				my $data = join '', @keys, $key3;
				use Digest::MD5 ();
				my $md5 = Digest::MD5::md5($data);
				$headers->{'sec-websocket-origin'}   ||= delete $headers->{'websocket-origin'}   || $self->{headers}{origin};
				$headers->{'sec-websocket-location'} ||= delete $headers->{'websocket-location'} || do {
					my $loc = URI->new_abs($self->{uri}, "http://$self->{headers}{host}");
					$loc = "$loc";
					$loc =~ s{^http}{ws};
					$loc;
				};
				# Dont use response method here to avoid cleanup
				$self->{con}->response($self,101,'',msg => "Web Socket Protocol Handshake", headers => $headers);
				$self->{con}{h}->push_write($md5);
				my $ws = $self->{con}{srv}{websocket_class}->new(
					con => $self->{con},
					version => 76,
				);
				$self->dispose;
				return $cb->($ws);
				#$self->error(501, '', msg => "Not Implemented WebSockets Protocol v76+");
				#return $cb->(undef, "Protocol version 76 not supported yet");
			});
		}
		elsif (exists $self->{headers}{'sec-websocket-version'}) {
			my $v = $self->{headers}{'sec-websocket-version'};
			warn "WebSocket RFC: Version $v\n";
			$self->{con}->access_log( ws => 1, m => "WebSocket version $v" );
			if ($v == 13) {
				my $key = $self->{headers}{'sec-websocket-key'};
				my $origin = exists $self->{headers}{'sec-websocket-origin'} ? $self->{headers}{'sec-websocket-origin'} : $self->{headers}{'origin'};
				#warn "key = $key; origin = $origin";
				my $acc = $key . '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
				$acc = encode_base64(sha1($acc));
				chomp $acc;
				$headers->{'Sec-WebSocket-Accept'} = $acc;
				#$headers->{'Sec-WebSocket-Protocol'} = $subtype || 'chat'
					;#if exists $self->{headers}{'sec-websocket-protocol'} or defined $subtype;
				
				$self->{con}->response($self,101,'',msg => "Web Socket Protocol Handshake", headers => $headers);
				#$self->{con}{h}->push_write($md5);
				my $ws = $self->{con}{srv}{websocket_class}->new(
					con => $self->{con},
					version => $v,
				);
				$self->dispose;
				return $cb->($ws);
			} else {
				warn "Unsupported";
				$self->error(400, '', msg => "Not Implemented WebSockets Protocol v$v", headers => {
					'Sec-WebSocket-Version' => 13
				});
			}
		}
		else {
			$headers->{'websocket-origin'}   ||= $self->{headers}{origin};
			$headers->{'websocket-location'} ||= do {
				my $loc = URI->new_abs($self->{uri}, "http://$self->{headers}{host}");
				$loc = "$loc";
				$loc =~ s{^http}{ws};
				$loc;
			};
			# Dont use response method here to avoid cleanup
			$self->{con}->response($self,101,'',msg => "Web Socket Protocol Handshake", headers => $headers);
			#warn "$self have\n\t con=$self->{con}\n\tsrv=$self->{con}{srv}\n\tws=$self->{con}{srv}{websocket_class}\n";
			my $ws = $self->{con}{srv}{websocket_class}->new(
				con => $self->{con},
			);
			$self->dispose;
			return $cb->($ws);
		}
	}
	else {
		return $cb->(undef, "Unsupported upgrade type: $type");
	}
}

sub response {
	my $self = shift;
	#warn "Response @_";
	$self->{con} or return $self->dispose;
	$self->{con}->response($self, @_);
	$self->dispose;
}
*respond = \&response;

sub error {
	my $self = shift;
	my $code = shift;
	$self->{con} or return warn("Called error($code) on destroyed object"),%$self = ();
	$self->{con}->response($self, $code, @_);
	$self->dispose;
}

sub go {
	warn "go @_";
	my $self = shift;
	my $location = shift;
	my $code = @_ % 2 ? shift : 302;
	my %args = @_;
	my $headers = delete $args{headers} || {};
	$headers->{location} = $location;
	$code ||= 302;
	$self->response($code, '', %args, headers => $headers);
}

sub dispose {
	my $self = shift;
	return %$self = ();
}

sub DESTROY {
	my $self = shift;
	$self->{con} or return %$self = ();
	$self->{con}->response($self, 404, '', msg => "Request '$self->{uri}' not handled");
}



1;
