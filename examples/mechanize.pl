#!/usr/bin/perl

package Test::WWW::Mechanize::CGI;

use strict;
use warnings;
use base 'Test::WWW::Mechanize';

use CGI;
use HTTP::Request;
use HTTP::Request::AsCGI;

sub cgi {
    my $self = shift;

    if ( @_ ) {
        $self->{cgi} = shift;
    }

    return $self->{cgi};
}

sub _make_request {
    my ( $self, $request ) = @_;

    $self->cookie_jar->add_cookie_header($request) if $self->cookie_jar;

    my $c = HTTP::Request::AsCGI->new($request)->setup;
    $self->cgi->();
    my $response = $c->restore->response;

    $response->header( 'Content-Base', $request->uri );
    $response->request($request);
    $self->cookie_jar->extract_cookies($response) if $self->cookie_jar;
    return $response;
}

package main;

use strict;
use warnings;

use Test::More tests => 3;

my $mech = Test::WWW::Mechanize::CGI->new;
$mech->cgi( sub {

    CGI::initialize_globals();

    my $q = CGI->new;

    print $q->header, 
          $q->start_html('Hello World'), 
          $q->h1('Hello World'),
          $q->end_html;   
});

$mech->get_ok('http://localhost/');
$mech->title_is('Hello World');
$mech->content_contains('Hello World');
