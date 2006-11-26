#!perl

use Test::More tests => 3;

{
    eval "use PerlIO::scalar";
    plan skip_all => 'PerlIO::scalar required' if $@;
}

use strict;
use warnings;

use HTTP::Request;
use HTTP::Request::AsCGI;

my $r = HTTP::Request->new( POST => 'http://www.host.com/');
$r->content('STDIN');
$r->content_length(5);
$r->content_type('text/plain');

open( my $stdin, ' +<', \( my $stdin_scalar ) )
  or die qq/Couldn't open a new PerlIO::scalar/;

open( my $stdout, '+>', \( my $stdout_scalar ) )
  or die qq/Couldn't open a new PerlIO::scalar/;

open( my $stderr, '+>', \( my $stderr_scalar ) )
  or die qq/Couldn't open a new PerlIO::scalar/;

my $c = HTTP::Request::AsCGI->new(
    request => $r,
    dup     => 0,
    stdin   => $stdin,
    stdout  => $stdout,
    stderr  => $stderr
);

$c->setup;

print STDOUT 'STDOUT';
print STDERR 'STDERR';

$c->restore;

is( $c->stdin->getline,  'STDIN',  'STDIN' );
is( $c->stdout->getline, 'STDOUT', 'STDOUT' );
is( $c->stderr->getline, 'STDERR', 'STDERR' );
