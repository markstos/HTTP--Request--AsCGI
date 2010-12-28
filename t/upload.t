#!perl

# Test that a file upload produces the expected content.

use Test::More;

use strict;
use warnings;

use HTTP::Request;
use HTTP::Request::Common;
use HTTP::Request::AsCGI;

local %ENV;

eval 'require CGI';
if ($@) {
   plan skip_all => 'need CGI.pm for tests tests';
}
else  {
   plan tests => 3;
};

my $c = HTTP::Request::AsCGI->new(
    POST "/",
        Content_Type => 'form-data',
        Content => [ foo => [ "t/upload.t" ] ],
)->setup;

my $q = CGI->new;

is($q->param('foo'), 'upload.t', "file field name is found in param() as expected");
is($q->param('missing'), undef, "reality check: form param not expected");

my $fh = $q->upload('foo');

my $line;
read($fh, $line, 20);
like($line,qr/perl/, "uploaded file has expected content"); 


