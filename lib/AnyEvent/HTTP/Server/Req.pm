package AnyEvent::HTTP::Server::Req;

use common::sense;
use HTTP::Easy::Status;
use HTTP::Easy::Headers;
use URI;

sub new {
	my $pk = shift;
	my $self = bless {@_},$pk;
	$self->{uri} = URI->new($self->{uri});
	$self;
}

sub wants_websocket {
	my $self = shift;
	return lc $self->{headers}{connection} eq 'upgrade' && lc $self->{headers}{upgrade} eq 'websocket' ? 1 : 0;
}

sub upgrade {
	my $self = shift;
	my $cb = pop;
	my $type = shift;
	my $headers = shift || HTTP::Easy::Headers->new({});
	if (lc $type eq 'websocket') {
		$headers->{upgrade}    = 'WebSocket';
		$headers->{connection} = 'Upgrade';
		if (exists $self->{headers}{'sec-websocket-key1'}) {
			$self->{con}{h}->push_read(chunk => 8, sub {
				shift;
				my $key3 = shift;
				my @keys = @{ $self->{headers} }{qw( sec-websocket-key1 sec-websocket-key2)};
				for my $key (@keys) {
					my $sp = $key =~ s/ //g;
					$key =~ s/\D+//g;
					warn "key extract = $key / $sp";
					$key = int ($key / $sp);
					$key = pack N => $key;
					warn sprintf "%08b", $key;
					warn "Got key<$key/$sp>";
				}
				warn "keys = [@keys]";
				my $data = join '', @keys, $key3;
				warn "Have data=<$data>";
				use Digest::MD5 ();
				my $md5 = Digest::MD5::md5($data);
				warn "Have md5=<$md5>";
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
				#$self->error(501, '', msg => "Not Implemented WebSockets Protocol v76+");
				#return $cb->(undef, "Protocol version 76 not supported yet");
			});
		} else {
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
		}
		my $ws = $self->{con}{srv}{websocket_class}->new(
			con => $self->{con},
		);
		$self->dispose;
		return $cb->($ws);
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

sub error {
	my $self = shift;
	my $code = shift;
	$self->{con} or return warn("Called error($code) on destroyed object"),%$self = ();
	$self->{con}->response($self, $code, @_);
	$self->dispose;
}

sub dispose {
	my $self = shift;
	return %$self = ();
}

sub DESTROY {
	my $self = shift;
	$self->{con} or return %$self = ();
	$self->{con}->response($self, 404, '', msg => "Request not handled");
}



1;
