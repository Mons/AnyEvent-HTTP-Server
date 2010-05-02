use inc::Module::Install;

name     'AnyEvent-HTTP-Server';
all_from 'lib/AnyEvent/HTTP/Server.pm';
author   'Mons Anderson <mons@cpan.org>';
license  'perl';

build_requires 'Test::More';

requires 'AnyEvent', 5;
requires 'AnyEvent::Handle::Writer';
requires 'HTTP::Easy';

auto_install;

WriteAll;

