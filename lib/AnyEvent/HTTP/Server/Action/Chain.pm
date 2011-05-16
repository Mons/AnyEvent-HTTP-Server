package AnyEvent::HTTP::Server::Action::Chain;

use uni::perl;

sub new {
	my $pk = shift;
	my $self = bless {@_}, $pk;
	$self;
}

sub handle {
	my ($self,$r,$data) = @_;
	for my $c (@{$self->{chain}}) {
		my $rs =
			UNIVERSAL::can($c,'handle') ? $c->handle($r,$data) :
			UNIVERSAL::isa($c,'CODE') ? $c->($r,$data) :
			warn( "'$c' can't be used as a handler." ),next;
		if ($rs) {
			return 1;
		} else {
			
		}
	}
	return 0;
}

1;
