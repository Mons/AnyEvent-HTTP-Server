package AnyEvent::HTTP::Server::WebSocket;

use common::sense;
use URI;
use Encode;

no utf8;
use bytes;

our $UTF = Encode::find_encoding('utf-8') or die "No utf-8 encoding found";

sub new {
	my $pk = shift;
	my $self = bless {@_},$pk;
	$self->{con}{h}->on_eof(sub { warn "EOF WS"; } );
	$self->{con}{h}->on_error(sub { warn "ERR WS @_"; } );
	$self;
}

sub onmessage {
	my $self = shift;
	if (@_) {
		$self->{recv} = shift;
		if ($self->{recv}) {
			$self->reader;
		}
		return;
	}
	$self->{recv};
}

sub log:method {
	my $self = shift;
	$self->{con} or return;
	$self->{con}->log(@_);
}

sub send : method {
	my $self = shift;
	#$self->{con} or return;
	my $data = shift;
	my $bytes = $UTF->encode($UTF->decode($data));
	$self->log("[ws.send:text] %d bytes", length $bytes);
	$self->{con}{h}->push_write(
		"\x00".$bytes."\xff"
	);
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

sub reader {
	my $self = shift;
	$self->{con}{h}->push_read(chunk => 1, sub {
		my $h = shift;
		my $first = shift;
		my $byte = ord($first);
		if ($first & 0x80 == 0x80) {
			#$self->log("Need binary frame");
			$h->unshift_read(regex => qr{^[\x80-\xff]+[\x00-\x7f]}, sub {
				use integer;
				shift;
				my $length = 0;
				my @bytes = map +ord, $first, split //,shift;
				while (@bytes) {
					my $byte = shift(@bytes) & 0x7f;
					$length = $length * 128 + $byte;
				}
				$h->unshift_read(chunk => $length, sub {
					shift;
					$self->log("[ws.recv:binary] %d bytes", length $_[0]);
					$self->{recv}($_[0]);
					$self->reader;
				});
			});
		}
		else {
			# Text frame
			#$self->log("Need text frame");
			$self->{con}{h}->unshift_read(line => qr{\x{ff}}, sub {
				shift;
				my $val = shift;
				#utf8::encode($val) if utf8::is_utf8($val);
				my $utf = $UTF->decode($val);
				$self->log("[ws.recv:text] %d bytes", length $val);
				$self->{recv}($utf);
				$self->reader;
			});
		}
	});
}

1;
