package AnyEvent::HTTP::Server::WebSocket;

use common::sense;
use URI;
use Encode;

no utf8;
use bytes;
use uni::perl ':dumper';
use JSON::XS;
use Scalar::Util 'weaken';
use Time::HiRes 'time';

our $JSON = JSON::XS->new->utf8;#->pretty;
our $UTF = Encode::find_encoding('utf-8') or die "No utf-8 encoding found";

use constant GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
use constant DEBUG => 0;
use constant {
  CONTINUATION => 0,
  TEXT         => 1,
  BINARY       => 2,
  CLOSE        => 8,
  PING         => 9,
  PONG         => 10
};
BEGIN {
	if (DEBUG) {
		require Devel::Hexdump;
		Devel::Hexdump->import( 'xd' );
	} else {
		*xd = sub {};
	}
}

our %OP = (
	CONTINUATION() => 'CONT',
	TEXT()         => 'TEXT',
	BINARY()       => 'BINARY',
	CLOSE()        => 'CLOSE',
	PING()         => 'PING',
	PONG()         => 'PONG',
);

use Config;
sub DEBUG() { 0 }
sub max_websocket_size { 262144 }

sub access_log {
	my $self = shift;
	#$self->{access_log} and return $self->{access_log}($self,@_);
	my %args = @_;
	my $type;
	my $op;
	if (exists $args{send}) {
		$type = "send";
		$op = $args{send};
	} else {
		$type = "recv";
		$op = $args{recv};
	}
	return if $op == PING or $op == PONG;
	if (-t STDERR) {
		print STDERR "\e[".do {
			$args{err} ? "1;31" :
			$args{send} ? "36" : "35";
		}."m";
	}
	printf STDERR
		"%08x(%d) %s:%d WS$self->{version} %1s-%1s ", $self->{con}{id},$self->{con}{fileno}, $self->{con}{host},$self->{con}{port}, $args{send}&&'<', $args{recv}&&'>';
	
	if ($args{err}) {
		printf STDERR "[%s] %s", $args{err}, $args{m};
	} else {
		printf STDERR "[%s] %db", $OP{$op} || 'UNK', exists $args{bytes} ? $args{bytes} : exists $args{data} ? length ${ $args{data} } : '-1';
		printf STDERR " (%s)", ${$args{data}} if exists $args{data} and $op == PING or $op == PONG or $op == TEXT;
	}
	
	if (-t STDERR) {
		print STDERR "\e[0m";
	}
	print STDERR "\n";
}


sub new {
	my $pk = shift;
	my $self = bless {@_},$pk;
	my $h = delete $self->{con}{h};
	delete $self->{con}{ka};
	$self->{h} = $h;
	
	weaken(my $this = $self);
	
	$self->{h}->on_eof(sub {
		$this or return;
		$this->destroy("EOF");
	} );
	$self->{h}->on_error(sub {
		$this or return;
		$this->destroy("@_");
	} );
	$self;
}

sub destroy {
	my $self = shift;
	my $err = @_ ? "ERR" : "DES";
	$self->{close} and $self->{close}();
	$self->access_log( err => $err, m => shift() );
	delete $self->{timers};
	$self->{h} and (delete $self->{h})->destroy;
	%$self = ();
}

sub set_ping {
	weaken( my $this = shift );
	if (!@_ or !$_[0]) {
		delete $this->{timers}{ping};
		return;
	}
	my $interval = shift;
	if ($this->{version} == 13) {
		$this->{timers}{ping} = AE::timer $interval,$interval,sub {
			$this or return;
			$this->send_frame(1, 0, 0, 0, PING, time());
		};
	} else {
		warn "Don't know how to ping $this->{version}";
	}
}

sub onmessage {
	my $self = shift;
	#die "N/I";
	if (@_) {
		$self->{recv} = shift;
		if ($self->{recv}) {
			if ($self->{version} == 76) {
				$self->reader_v76;
			}
			elsif ($self->{version} == 13) {
				$self->{h}->on_read(sub {
					#warn "ready for read \n".xd "$_[0]{rbuf}";
					while (my $frame = $self->parse_frame(\( $_[0]{rbuf} ))) {
						my $op = $frame->[4] || CONTINUATION;
						$self->access_log( recv => $op, data => \($frame->[5]) );
						$self->send_frame(1, 0, 0, 0, PONG, $frame->[5]) and next if $op == PING;
						
						if ($op == PONG) {
							#warn "Received pong to $frame->[5]";
							next;
						};
						$self->finish and next if $op == CLOSE;
						
						#next unless $self->has_subscribers('message');
						
						$self->{op} = $op unless exists $self->{op};
						$self->{message} .= $frame->[5];
						$self->finish and last if length $self->{message} > $self->max_websocket_size;
						next unless $frame->[0];
						
						my $message = $self->{message};
						$self->{message} = '';
						$message = $UTF->decode( $message ) if length $message and delete $self->{op} == TEXT;
						
						$self->{recv}($message);
						
						#warn dumper $frame;
					}
					return;
				});
				$self->{h}->start_read;
				return;
			}
			else {
				warn "Don't know how to read from $self->{version} ".dumper $self->{h};
			}
		}
		return;
	}
	$self->{recv};
}

sub _xor_mask {
  my ($input, $mask) = @_;

  # 512 byte mask
  $mask = $mask x 128;
  local $_;
  my $output = '';
  $output .= $_ ^ $mask while ( length($_ = substr($input, 0, 512, '')) == 512 );
  $output .= $_ ^ substr($mask, 0, length, '');

  return $output;
}


sub parse_frame {
	my ($self,$rbuf) = @_;
	return if length $$rbuf < 2;
	my $check = $AnyEvent::Loop::fds[0][1][ fileno $self->{h}{fh} ][0];
	#warn dumper $check;
	my $clone = $$rbuf;
	#say "parsing frame: \n".xd "$clone";
	my $head = substr $clone, 0, 2;
	my $fin = (vec($head, 0, 8) & 0b10000000) == 0b10000000 ? 1 : 0;
	my $rsv1 = (vec($head, 0, 8) & 0b01000000) == 0b01000000 ? 1 : 0;
	warn "RSV1: $rsv1\n" if DEBUG;
  my $rsv2 = (vec($head, 0, 8) & 0b00100000) == 0b00100000 ? 1 : 0;
  warn "RSV2: $rsv2\n" if DEBUG;
  my $rsv3 = (vec($head, 0, 8) & 0b00010000) == 0b00010000 ? 1 : 0;
  warn "RSV3: $rsv3\n" if DEBUG;

  # Opcode
  my $op = vec($head, 0, 8) & 0b00001111;
  warn "OPCODE: $op\n" if DEBUG;

  # Length
  my $len = vec($head, 1, 8) & 0b01111111;
  warn "LENGTH: $len\n" if DEBUG;

  # No payload
  my $hlen = 2;
  if ($len == 0) { warn "NOTHING\n" if DEBUG }

  # Small payload
  elsif ($len < 126) { warn "SMALL\n" if DEBUG }

  # Extended payload (16bit)
  elsif ($len == 126) {
    return unless length $clone > 4;
    $hlen = 4;
    my $ext = substr $clone, 2, 2;
    $len = unpack 'n', $ext;
    warn "EXTENDED (16bit): $len\n" if DEBUG;
  }

  # Extended payload (64bit)
  elsif ($len == 127) {
    return unless length $clone > 10;
    $hlen = 10;
    my $ext = substr $clone, 2, 8;
    $len =
      $Config{ivsize} > 4
      ? unpack('Q>', $ext)
      : unpack('N', substr($ext, 4, 4));
    warn "EXTENDED (64bit): $len\n" if DEBUG;
  }

  # Check message size
  $self->finish and return if $len > $self->max_websocket_size;

  # Check if whole packet has arrived
  my $masked = vec($head, 1, 8) & 0b10000000;
  return if length $clone < ($len + $hlen + ($masked ? 4 : 0));
  substr $clone, 0, $hlen, '';

  # Payload
  $len += 4 if $masked;
  return if length $clone < $len;
  my $payload = $len ? substr($clone, 0, $len, '') : '';

  # Unmask payload
  if ($masked) {
    warn "UNMASKING PAYLOAD\n" if DEBUG;
    my $mask = substr($payload, 0, 4, '');
    $payload = _xor_mask($payload, $mask);
  }
  warn "PAYLOAD: $payload\n" if DEBUG;
  $$rbuf = $clone;

	return [$fin, $rsv1, $rsv2, $rsv3, $op, $payload];
}

sub onclose {
	my $self = shift;
	if (@_) {
		$self->{close} = shift;
		return;
	}
	$self->{close};
}

sub log:method {
	my $self = shift;
	$self->{con} or return;
	$self->{con}->log(@_);
}

sub finish {
	my $self = shift;
	$self->send_frame(1, 0, 0, 0, CLOSE, '');
	$self->{close} and $self->{close}();
	$self->{h} and $self->{h}->destroy;
	%$self = ();
	return 1;
}

sub build_frame {
  my ($self, $fin, $rsv1, $rsv2, $rsv3, $op, $payload) = @_;
  warn "BUILDING FRAME\n" if DEBUG;

  # Head
  my $frame = 0b00000000;
  vec($frame, 0, 8) = $op | 0b10000000 if $fin;
  vec($frame, 0, 8) |= 0b01000000 if $rsv1;
  vec($frame, 0, 8) |= 0b00100000 if $rsv2;
  vec($frame, 0, 8) |= 0b00010000 if $rsv3;

  # Mask payload
  warn "PAYLOAD: $payload\n" if DEBUG;
  my $masked = 0;#$self->masked;
  if ($masked) {
    warn "MASKING PAYLOAD\n" if DEBUG;
    my $mask = pack 'N', int(rand 9999999);
    $payload = $mask . _xor_mask($payload, $mask);
  }

  # Length
  my $len = length $payload;
  $len -= 4 if $masked;

  # Empty prefix
  my $prefix = 0;

  # Small payload
  if ($len < 126) {
    vec($prefix, 0, 8) = $masked ? ($len | 0b10000000) : $len;
    $frame .= $prefix;
  }

  # Extended payload (16bit)
  elsif ($len < 65536) {
    vec($prefix, 0, 8) = $masked ? (126 | 0b10000000) : 126;
    $frame .= $prefix;
    $frame .= pack 'n', $len;
  }

  # Extended payload (64bit)
  else {
    vec($prefix, 0, 8) = $masked ? (127 | 0b10000000) : 127;
    $frame .= $prefix;
    $frame .=
      $Config{ivsize} > 4
      ? pack('Q>', $len)
      : pack('NN', $len >> 32, $len & 0xFFFFFFFF);
  }

  if (DEBUG) {
    warn 'HEAD: ', unpack('B*', $frame), "\n";
    warn "OPCODE: $op\n";
  }

  # Payload
  $frame .= $payload;
  print "Built frame = \n".xd "$frame" if DEBUG;

  return $frame;
}


sub send_frame {
	my ($self, $fin, $rsv1, $rsv2, $rsv3, $op, $payload) = @_;
	$self->{h} or return warn "Failed to send $OP{$op}: no handle";
	my $f = $self->build_frame($fin, $rsv1, $rsv2, $rsv3, $op, $payload);
	$self->access_log( send => $op, fin => $fin, bytes => length $f, data => \$payload );
	$self->{h}->push_write($f);
}

sub send : method {
	my $self = shift;
	#$self->{con} or return;
	if ($self->{version} == 76) {
		my $data = shift;
		utf8::encode $data if utf8::is_utf8($data);
		$self->log("[ws.send:text] %d bytes", length $data);
		$self->{h}->push_write(
			"\x00".$data."\xff"
		);
	}
	elsif ($self->{version} == 13) {
		my $m = shift;
		utf8::encode $m if utf8::is_utf8($m);
		if (ref $m) {
			$self->send_frame(1, 0, 0, 0, ($m->[0] eq 'text' ? TEXT : BINARY ), $m->[1])
		} else {
			$self->send_frame(1, 0, 0, 0, TEXT, $m);
		}
	}
	else {
		warn "Can't send on v$self->{version}";
	}
}

sub jsend {
	my $self = shift;
	my $j = $JSON->encode($_[0]);
	$self->send( $j );
}

#     ; the wire protocol as allowed by this specification
#     frames        = *frame
#     frame         = text-frame
#     text-frame    = (%x00) *( UTF8-char ) %xFF
#
#     ; the wire protocol including error-handling and forward-compatible parsing rules
#     frames        = *frame
#     frame         = text-frame / binary-frame
#     text-frame    = (%x00-%x7F) *( UTF8-char / %x80-%x7E ) %xFF
#     binary-frame  = (%x80-%xFF) length < as many bytes as given by the length >
#     length        = *(%x80-%xFF) (%x00-%x7F)

sub reader_v76 {
	my $self = shift;
	#die "N/I";
	$self->{h}->push_read(chunk => 1, sub {
		my $h = shift;
		my $first = shift;
		my $byte = ord($first);
		if ($first & 0x80 == 0x80) {
			$self->log("Need binary frame");
			$h->unshift_read(regex => qr{^[\x80-\xff]*[\x00-\x7f]}, sub {
				use integer;
				shift;
				my $length = 0;
				my @bytes = map +ord, $first, split //,shift;
				while (@bytes) {
					my $byte = shift(@bytes) & 0x7f;
					$length = $length * 128 + $byte;
				}
				if ($first == 0xff and $length == 0) {
					warn "Received close handshake";
					$h->push_write("\xff\x00");
					$self->{close} and (delete $self->{close})->();
					$self->{con}->close;
				}
				else {
					$h->unshift_read(chunk => $length, sub {
						shift;
						$self->log("[ws.recv:binary] %d bytes", length $_[0]);
						$self->{recv}($_[0]);
						$self->reader_v76;
					});
				}
			});
		}
		else {
			# Text frame
			$self->log("Need text frame");
			$self->{h}->unshift_read(line => qr{\x{ff}}, sub {
				shift;
				my $val = shift;
				#utf8::encode($val) if utf8::is_utf8($val);
				my $utf = $UTF->decode($val);
				$self->log("[ws.recv:text] %d bytes", length $val);
				$self->{recv}($utf);
				$self->reader_v76;
			});
		}
	});
}

1;
