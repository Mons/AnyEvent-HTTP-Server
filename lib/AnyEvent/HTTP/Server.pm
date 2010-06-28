package AnyEvent::HTTP::Server;

use common::sense;

=head1 NAME

AnyEvent::HTTP::Server - AnyEvent HTTP/1.1 server with websockets

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    TODO

=cut

use uni::perl ':dumper';
use AE 5;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Scalar::Util qw(weaken);
use Sys::Sendfile;
use HTTP::Easy::Headers;

use AnyEvent::HTTP::Server::Con;
use AnyEvent::HTTP::Server::Req;
use AnyEvent::HTTP::Server::WebSocket;

sub new {
	my $pk = shift;
	my $self = bless {
		keep_alive => 1,
		connection_class => 'AnyEvent::HTTP::Server::Con',
		request_class    => 'AnyEvent::HTTP::Server::Req',
		websocket_class  => 'AnyEvent::HTTP::Server::WebSocket',
		@_,
		con => {},
	},$pk;
	if ($self->{socket}) {
		
	} else {
		$self->{host} //= '0.0.0.0';
		$self->{port} //= 8080;
	}
	return $self;
}

sub start {
	my $self = shift;
	if ($self->{socket}) {
		warn "Starting server on socket\n";
		# <Derived from AnyEvent::Socket>
		$self->{aw} = AE::io $self->{socket}, 0, sub {
			while ($self->{socket} && (my $peer = accept my $fh, $self->{socket})) {
				binmode($fh,':raw');
				AnyEvent::Util::fh_nonblocking $fh, 1;
				select((select($fh),$| = 1)[0]);
				my ($service, $host) = AnyEvent::Socket::unpack_sockaddr($peer);
				$self->accept($fh, AnyEvent::Socket::format_address($host), $service);
			}
		};
		# </Derived from AnyEvent::Socket>
	} else {
		warn "Starting server on port $self->{port}\n";
		tcp_server $self->{host}, $self->{port}, sub {
			my $fh = shift or return warn "couldn't accept client: $!";
			my ($host, $port) = @_;
			$self->accept($fh,$host, $port);
		}, sub {
			#my $fh = shift or return warn "couldn't accept client: $!";
			#setsockopt($fh, SOL_SOCKET, SO_REUSEADDR, 1) or die "Can't set socket option: $!";
			1024;
		};
	}
	warn "Ready";
}

sub accept :method {
	my ($self,$fh,$host,$port) = @_;
	my $con = $self->{connection_class}->new(
		server   => $self,
		fh       => $fh,
		host     => $host,
		port     => $port,
		on_error => sub {
			my $con = shift;
			warn "@_";
			delete $self->{con}{$con->{id}};
		},
	);
	$self->{con}{$con->{id}} = $con;
	return;
}

sub handle_request {
	my ($self,$r,$data) = @_;
	#warn "Handle request";
	weaken(my $x = $r);
	$r->{t} = AE::timer 5,0,sub {
		$x or return;
		warn "Fire timeout timer";
		$x->response(504, msg => "Gateway timeout");
	};
	$self->{request} or return;
	if (UNIVERSAL::can($self->{request},'handle')) {
		$self->{request}->handle($r,$data);
	} else {
		$self->{request}->($r,$data);
	}
}

=head1 RESOURCES

=over 4

=item * GitHub repository

L<http://github.com/Mons/AnyEvent-HTTP-Server>

=back

=head1 ACKNOWLEDGEMENTS

=over 4

=item * Thanks to B<Marc Lehmann> for L<AnyEvent>

=item * Thanks to B<Robin Redeker> for L<AnyEvent::HTTPD>. Parts of that module was derived from

=back

=head1 AUTHOR

Mons Anderson, <mons@cpan.org>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

=cut

1; # End of AnyEvent::HTTP::Server
