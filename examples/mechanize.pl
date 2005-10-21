#!/usr/bin/perl

package Test::WWW::Mechanize::CGI;

use strict;
use warnings;
use base 'Test::WWW::Mechanize';

use HTTP::Request;
use HTTP::Request::AsCGI;
use HTTP::Response;

sub cgi {
    my $self = shift;

    if ( @_ ) {
        $self->{cgi} = shift;
    }

    return $self->{cgi};
}

sub _make_request {
    my ( $self, $request ) = @_;

    if ( $self->cookie_jar ) {
        $self->cookie_jar->add_cookie_header($request);
    }

    my $c = HTTP::Request::AsCGI->new($request)->setup;

    eval { $self->cgi->() };

    my $response;

    if ( $@ ) {
        $response = HTTP::Response->new(500);
        $response->date( time() );
        $response->content( $response->error_as_HTML );
    }
    else {
        $response = $c->restore->response;
    }

    $response->header( 'Content-Base', $request->uri );
    $response->request($request);

    if ( $self->cookie_jar ) {
        $self->cookie_jar->extract_cookies($response);
    }

    return $response;
}

package main;

use strict;
use warnings;

use CGI;
use Test::More tests => 3;

my $mech = Test::WWW::Mechanize::CGI->new;
$mech->cgi( sub {

    my $q = CGI->new;

    print $q->header,
          $q->start_html('Hello World'),
          $q->h1('Hello World'),
          $q->end_html;
});

$mech->get_ok('http://localhost/');
$mech->title_is('Hello World');
$mech->content_contains('Hello World');
