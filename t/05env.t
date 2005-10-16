#!perl

use Test::More tests => 8;

use strict;
use warnings;

use IO::File;
use HTTP::Request;
use HTTP::Request::AsCGI;

my $r = HTTP::Request->new( GET => 'http://www.host.com/cgi-bin/script.cgi?a=1&b=2' );
my $c = HTTP::Request::AsCGI->new($r);
$c->stdout( IO::File->new_from_fd( STDOUT->fileno, '>' ) );
$c->stderr( IO::File->new_from_fd( STDERR->fileno, '>' ) );

$c->setup;

is( $ENV{GATEWAY_INTERFACE}, 'CGI/1.1', 'GATEWAY_INTERFACE' );
is( $ENV{HTTP_HOST}, 'www.host.com:80', 'HTTP_HOST' );
is( $ENV{QUERY_STRING}, 'a=1&b=2', 'QUERY_STRING' );
is( $ENV{SCRIPT_NAME}, '/', 'SCRIPT_NAME' );
is( $ENV{REQUEST_METHOD}, 'GET', 'REQUEST_METHOD' );
is( $ENV{SERVER_NAME}, 'www.host.com', 'SERVER_NAME' );
is( $ENV{SERVER_PORT}, '80', 'SERVER_PORT' );

$c->restore;

is( $ENV{GATEWAY_INTERFACE}, undef, 'No CGI env after restore' );
