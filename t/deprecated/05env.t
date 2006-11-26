#!perl

use Test::More tests => 12;

use strict;
use warnings;

use HTTP::Request;
use HTTP::Request::AsCGI;

my $r = HTTP::Request->new( GET => 'http://www.host.com/cgi-bin/script.cgi/my/path/?a=1&b=2', [ 'X-Test' => 'Test' ] );
   $r->authorization_basic( 'chansen', 'xxx' );
my %e = ( SCRIPT_NAME => '/cgi-bin/script.cgi' );
my $c = HTTP::Request::AsCGI->new( $r, %e );

$c->stdout(undef);
$c->setup;

is( $ENV{GATEWAY_INTERFACE}, 'CGI/1.1', 'GATEWAY_INTERFACE' );
is( $ENV{HTTP_HOST}, 'www.host.com:80', 'HTTP_HOST' );
is( $ENV{HTTP_X_TEST}, 'Test', 'HTTP_X_TEST' );
is( $ENV{PATH_INFO}, '/my/path/', 'PATH_INFO' );
is( $ENV{QUERY_STRING}, 'a=1&b=2', 'QUERY_STRING' );
is( $ENV{AUTH_TYPE}, 'Basic', 'AUTH_TYPE' );
is( $ENV{REMOTE_USER}, 'chansen', 'REMOTE_USER' );
is( $ENV{SCRIPT_NAME}, '/cgi-bin/script.cgi', 'SCRIPT_NAME' );
is( $ENV{REQUEST_METHOD}, 'GET', 'REQUEST_METHOD' );
is( $ENV{SERVER_NAME}, 'www.host.com', 'SERVER_NAME' );
is( $ENV{SERVER_PORT}, '80', 'SERVER_PORT' );

$c->restore;

is( $ENV{GATEWAY_INTERFACE}, undef, 'No CGI env after restore' );
