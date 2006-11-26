#!perl

use Test::More tests => 3;

{
    eval "use IO::String 1.07";
    plan skip_all => 'IO::String 1.07 required' if $@;
}

use strict;
use warnings;

use HTTP::Request;
use HTTP::Request::AsCGI;

my $r = HTTP::Request->new( POST => 'http://www.host.com/');
$r->content('STDIN');
$r->content_length(5);
$r->content_type('text/plain');

my $c = HTTP::Request::AsCGI->new(
    request => $r,
    dup     => 0,
    stdin   => IO::String->new,
    stdout  => IO::String->new,
    stderr  => IO::String->new
);

$c->setup;

print STDOUT 'STDOUT';
print STDERR 'STDERR';

$c->restore;

is( $c->stdin->getline,  'STDIN',  'STDIN' );
is( $c->stdout->getline, 'STDOUT', 'STDOUT' );
is( $c->stderr->getline, 'STDERR', 'STDERR' );
