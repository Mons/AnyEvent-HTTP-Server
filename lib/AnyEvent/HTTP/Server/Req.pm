package AnyEvent::HTTP::Server::Req;

use common::sense;
use HTTP::Easy::Status;

sub new {
	my $pk = shift;
	my $self = bless {@_},$pk;
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
	my $headers = shift || {};
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
		$self->{server}->response($self,101,"Web Socket Protocol Handshake",$headers);
		my $ws = AE::HTTPD::WebSocket->new(
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
	warn "DESTROY request";
	$self->{con} or return %$self = ();
	$self->{con}->response($self, 500, msg => "No response");
}



1;
