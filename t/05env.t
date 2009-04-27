#!perl

use Test::More tests => 10;

use strict;
use warnings;

use HTTP::Request;
use HTTP::Request::AsCGI;

my $r = HTTP::Request->new( GET => 'http://www.host.com/cgi-bin/script.cgi/my%20path/?a=1&b=2', [ 'X-Test' => 'Test' ] );
my %e = ( SCRIPT_NAME => '/cgi-bin/script.cgi' );
my $c = HTTP::Request::AsCGI->new( $r, %e );
$c->stdout(undef);

$c->setup;

is( $ENV{GATEWAY_INTERFACE}, 'CGI/1.1', 'GATEWAY_INTERFACE' );
is( $ENV{HTTP_HOST}, 'www.host.com:80', 'HTTP_HOST' );
is( $ENV{HTTP_X_TEST}, 'Test', 'HTTP_X_TEST' );
TODO: {
    local $TODO = 'backed out as it breaks Catalyst';
    is( $ENV{PATH_INFO}, '/my path/', 'PATH_INFO' );
}
is( $ENV{QUERY_STRING}, 'a=1&b=2', 'QUERY_STRING' );
is( $ENV{SCRIPT_NAME}, '/cgi-bin/script.cgi', 'SCRIPT_NAME' );
is( $ENV{REQUEST_METHOD}, 'GET', 'REQUEST_METHOD' );
is( $ENV{SERVER_NAME}, 'www.host.com', 'SERVER_NAME' );
is( $ENV{SERVER_PORT}, '80', 'SERVER_PORT' );

$c->restore;

is( $ENV{GATEWAY_INTERFACE}, undef, 'No CGI env after restore' );
