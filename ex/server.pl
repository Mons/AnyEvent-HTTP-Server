#!/usr/bin/env perl

use uni::perl;
use lib::abs '../lib', 'lib';
use AnyEvent::Impl::Perl; # Better to use Impl::Perl for tests
use SampleServer;

use uni::perl;
use Log::Any::Adapter;
use Log::Dispatch::File;
use Log::Dispatch::Screen;
use Log::Dispatch::Config;
use Log::Dispatch::Configurator::Any;

# Setup Log::Any adapter to something you use. Log::Any is used by Daemond
Log::Dispatch::Config->configure(Log::Dispatch::Configurator::Any->new({
	format => '[%d{%T}] [%p] %m%n',
	dispatchers => [ 'screen', 'file' ],
	screen => { class => 'Log::Dispatch::Screen', stderr => 1, min_level => 'debug' },
	file   => { class => 'Log::Dispatch::File', mode => 'append', filename => lib::abs::path('debug.log'), min_level => 'debug' },
}));
Log::Any::Adapter->set( 'Dispatch', dispatcher => Log::Dispatch::Config->instance );


# Set your host and port here, and set the same in index.html
SampleServer->new({
	host => '89.208.136.108',
	port => 8081,
	pid  => '/tmp/websock.pid',
	root => lib::abs::path('root'),
})->run;

# now you can start your server in nodetach mode by
#
# $ perl server.pl -f start
#
# or in daemonized mode
#
# $ perl server.pl start
#
