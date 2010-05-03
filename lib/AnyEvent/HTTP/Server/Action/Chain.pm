package AnyEvent::HTTP::Server::Action::Chain;

use uni::perl;

sub new {
	my $pk = shift;
	my $self = bless {@_}, $pk;
	$self;
}

sub handle {
	my ($self,$r,$data) = @_;
	for (@{$self->{chain}}) {
		my $rs = UNIVERSAL::can($_,'handle') ? $_->handle($r,$data) : $_->($r,$data);
		if ($rs) {
			return 1;
		} else {
			
		}
	}
	return 0;
}

1;
