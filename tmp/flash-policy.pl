#!/usr/bin/perl

use uni::perl ':dumper';
use AE 5;
use AnyEvent::Socket;
use AnyEvent::Handle;

sub request {
	warn "Handle policy request\n";
	shift->(
		'site-control' => { 'permitted-cross-domain-policies' => 'master-only' },
		'allow-access-from' => { 'domain' => "*.rambler.ru", 'to-ports' => "1234" },
	);
}

tcp_server 0, 843, sub {
    #warn dumper \@_;
    my $fh = shift;
    my $h = AnyEvent::Handle->new(
        fh => $fh,
        on_error => sub { warn "ERROR: @_" },
        on_eof => sub { warn "EOF" },
    );
    $h->push_read(regex => qr{>},sub {
        shift;
        my $xml = shift;
				if ($xml =~ m{^\s*<policy-file-request\s*/>\s*$}) {
					request(sub {
						my $res;
						if (@_ == 1 and !ref $_[0]) {
							$res = shift;
						} else {
						my %args = @_;
						$res = '<?xml version="1.0" encoding="utf-8"?><cross-domain-policy>';
						while (my ($node,$value) = each %args) {
							$node =~ s{[^a-z0-9-]}{}sgo;
							$res .= '<'.$node;
							while (my ($k,$v) = each %$value) {
								$k =~ s{[^a-z0-9-]}{}sg;
								for ($v) {
									s{&}{&amp;}sgo;
									s{<}{&lt;}sgo;
									s{>}{&gt;}sgo;
									s{"}{&quot;}sgo; #"
								}
								$res .= qq{ $k="$v"};
							}
							$res .= ' />';
						}
						$res .= '</cross-domain-policy>';
						}
						$h->push_write($res."\0");
						$h->destroy;
					});
				} else {
					warn "Bad data: $xml";
					$h->destroy();
				}
    });
};


AE::cv->recv;