#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'AnyEvent::HTTP::Server' ) || print "Bail out!
";
}

diag( "Testing AnyEvent::HTTP::Server $AnyEvent::HTTP::Server::VERSION, Perl $], $^X" );
