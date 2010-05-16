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
		$headers->{upgrade} = 'WebSocket';
		$headers->{connection} = 'Upgrade';
		$headers->{'websocket-origin'} ||= $self->{headers}{origin};
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
	$self->{con} or return %$self = ();
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
