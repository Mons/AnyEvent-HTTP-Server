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

use Log::Any '$log';

sub new {
	my $pk = shift;
	my $self = bless {
		keep_alive => 1,
		connection_class => 'AnyEvent::HTTP::Server::Con',
		request_class    => 'AnyEvent::HTTP::Server::Req',
		websocket_class  => 'AnyEvent::HTTP::Server::WebSocket',
		request_timeout  => 30,
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
	my ($host,$port);
	if ($self->{socket}) {
		# <Derived from AnyEvent::Socket>
		($port, $host) = AnyEvent::Socket::unpack_sockaddr getsockname $self->{socket};
		$host = AnyEvent::Socket::format_address $host;
		$log->debug("Starting server on socket $host:$port");
		
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
		$log->debug("Starting server on $self->{host}:$self->{port}");
		$self->{aw} = tcp_server $self->{host}, $self->{port}, sub {
			my $fh = shift or return warn "couldn't accept client: $!";
			my ($host, $port) = @_;
			$self->accept($fh,$host, $port);
		}, sub {
			(undef,$host,$port) = @_;
			#my $fh = shift or return warn "couldn't accept client: $!";
			#setsockopt($fh, SOL_SOCKET, SO_REUSEADDR, 1) or die "Can't set socket option: $!";
			1024;
		};
	}
	$log->debug("Started server on $host:$port");
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
			$log->warn("@_");
			delete $self->{con}{$con->{id}};
		},
	);
	$self->{con}{$con->{id}} = $con;
	return;
}

sub stop {
	my ($self,$cb) = @_;
	delete $self->{aw};
	close $self->{socket};
	if (%{$self->{con}}) {
		$log->debugf("Server have %d active connectinos while stopping...", 0+keys %{$self->{con}});
		my $cv = &AE::cv( $cb );
		$cv->begin;
		for my $key ( keys %{$self->{con}} ) {
			my $con = $self->{con}{$key};
			$log->debug("$key: connection from $con->{host}:$con->{port}: $con->{state}");
			if ($con->{state} eq 'idle' or $con->{state} eq 'closed') {
				$con->close;
				delete $self->{con}{$key};
				use Devel::FindRef;
				warn "closed <$con> ".Devel::FindRef::track $con;
			} else {
				$cv->begin;
				$con->{close} = sub {
					$log->debug("Connection $con->{host}:$con->{port} was closed");
					$cv->end;
				};
			}
		}
		if (%{$self->{con}}) {
			$log->debug("Still have @{[ 0+keys %{$self->{con}} ]}");
		}
		$cv->end;
	} else {
		$cb->();
	}
}

sub handle_request {
	my ($self,$r,$data) = @_;
	$self->{request} or return;
	weaken(my $x = $r);
	my $timeout = $self->{request_timeout} || 30;
	$r->{t} = AE::timer $timeout, 0, sub {
		$x or return;
		$log->warn("Request handle timed out after $timeout seconds");
		$x->error(504);
	};
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
