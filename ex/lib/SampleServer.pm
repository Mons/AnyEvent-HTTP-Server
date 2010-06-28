package SampleServer;

# This is the Daemond's parent object
# It creates listen socked and forks on N workers.
# Count of workers should be choosen by number of CPUs/cores or your system

use uni::perl;
use Daemond -parent;

use accessors::fast qw(socket backlog);

# Use required modules earlier, to reside them in shared memory
use AnyEvent::HTTP::Server;
use AnyEvent::HTTP::Server::Action::Chain;
use AnyEvent::HTTP::Server::Action::Static;

name 'websockets';
cli;
proc;
children 1;          # How many children to fork

use Carp ();
use Errno ();
use Socket qw(AF_INET AF_UNIX SOCK_STREAM SOCK_DGRAM SOL_SOCKET SO_REUSEADDR);

use AnyEvent ();
use AnyEvent::Util qw(fh_nonblocking AF_INET6);
use AnyEvent::Socket ();

# Here we create socket and bind it. Rest of forking work will be done by Daemond
sub start {
    my $self = shift;
    $self->next::method(@_);
    $self->{backlog} ||= 1024;
    my ($host,$service,$root) = ($self->d->host, $self->d->port, $self->d->root);
    # <Derived from AnyEvent::Socket>
    $host = $AnyEvent::PROTOCOL{ipv4} < $AnyEvent::PROTOCOL{ipv6} && AF_INET6 ? "::" : "0"
        unless defined $host;

    my $ipn = AnyEvent::Socket::parse_address( $host )
        or Carp::croak "cannot parse '$host' as host address";

    my $af = AnyEvent::Socket::address_family( $ipn );

    Carp::croak "tcp_server/socket: address family not supported"
        if AnyEvent::WIN32 && $af == AF_UNIX;

    CORE::socket my $fh, $af, SOCK_STREAM, 0 or Carp::croak "socket: $!";
    if ($af == AF_INET || $af == AF_INET6) {
        setsockopt $fh, SOL_SOCKET, SO_REUSEADDR, 1 or Carp::croak "so_reuseaddr: $!"
            unless AnyEvent::WIN32; # work around windows bug

        $service = (getservbyname $service, "tcp")[2] or Carp::croak "$service: service unknown"
            unless $service =~ /^\d*$/
    }
    elsif ($af == AF_UNIX) {
        unlink $service;
    }

    bind $fh, AnyEvent::Socket::pack_sockaddr( $service, $ipn ) or Carp::croak "bind: $!";

    fh_nonblocking $fh, 1;

    {
        my ($service, $host) = AnyEvent::Socket::unpack_sockaddr( getsockname $fh );
        $host = AnyEvent::Socket::format_address($host);
        warn "Bind to $host:$service";
    }

    listen $fh, $self->{backlog} or Carp::croak "listen: $!";
    binmode($fh,':raw');
    # </Derived from AnyEvent::Socket>
    $self->{socket} = $fh;
    return;
}


package SampleServer::Child;

# This is the Daemond's child object
# It implements concrete, single worker
# It starts asyncronous AnyEvent::HTTP::Server on already prepared socket and serves requests

use uni::perl ':dumper';
use Daemond -child => 'SampleServer';

use accessors::fast qw(cv socket server);
use AnyEvent;
use AnyEvent::Handle;

sub start {
	my $self = shift;
	$self->{cv} = AE::cv;
	$self->{server} = AnyEvent::HTTP::Server->new(
		socket => $self->{socket},
		# Define a chain of 2 actions
		request => AnyEvent::HTTP::Server::Action::Chain->new(
			root => $self->d->root,
			chain => [
				sub { # Simple handler, takes request, and return 1 if request was handled by it to stop chain processing
					my $r = shift;
					my $rpath = $r->{uri}->path;
						if ($r->wants_websocket) {
							# Define 2 websocket locations /ws and /echo
							if ($rpath =~ m{^/ws/?}) {
								$r->upgrade('websocket', sub {     # Respond with upgrade
									if (my $ws = shift) {          # Receive websocket object
										$ws->onmessage(sub {       # Setup WebSocket on_message
											$ws->send("re: @_");
										});
										$ws->send("Hello!");       # Send initial "Hello!" from server
									} else {
										warn "Upgrade failed: @_";
									}
								});
								return 1;
							}
							elsif ( $rpath =~ m{^/echo/?$}) {
								$r->upgrade('websocket', sub {
									if (my $ws = shift) {
										$ws->onmessage(sub {
											$ws->send("@_");
										});
									} else {
										warn "Upgrade failed: @_";
									}
								});
								return 1;
							} else {
								# We have no such websockets location, return error and stop chain processing
								$r->error(400);
								return 1;
							}
						} else {
							# Pass request to next chain element
							return 0;
						}
				},
				# Use predefined action for serving static
				AnyEvent::HTTP::Server::Action::Static->new($self->d->root),
			],
		),
		policy_request => sub { # Also we can handle flash' policy request. It is required for websocket-flash
			warn "Handle policy request\n";
			shift->(
				'site-control' => { 'permitted-cross-domain-policies' => 'master-only' },
				'allow-access-from' => { 'domain' => "*", 'to-ports' => "80" },
			);
		},
	);
	return;
}

sub run {
	# Daemond method.
	my $self = shift;
	$self->{server}->start; # Start server
	$self->{cv}->recv;      # Run AnyEvent loop
	$self->log->debug("Correctly leaving loop");
}

sub stop_flag {
	# Daemond method. What to do on receiving TERM event
	my $self = shift;
	$self->{cv}->send;
}

1;
