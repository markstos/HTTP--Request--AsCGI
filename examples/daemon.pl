#!/usr/bin/perl

use strict;
use warnings;

use CGI;
use HTTP::Daemon;
use HTTP::Request;
use HTTP::Request::AsCGI;
use HTTP::Response;

$SIG{'PIPE'} = 'IGNORE';

my $server = HTTP::Daemon->new( LocalPort => 3000, ReuseAddr => 1 ) || die;

print "Please contact me at: <URL:", $server->url, ">\n";

while ( my $client = $server->accept ) {
    
    my %e = (
        REMOTE_ADDR => $client->peerhost,
        REMOTE_HOST => $client->peerhost,
        REMOTE_PORT => $client->peerport
    );

    while ( my $request = $client->get_request ) {

        CGI::initialize_globals();

        $request->uri->scheme('http');
        $request->uri->host_port( $request->header('Host') || URI->new($server)->host_port );

        my $c = HTTP::Request::AsCGI->new( $request, %e )->setup;
        my $q = CGI->new;

        print $q->header,
              $q->start_html('Hello World'),
              $q->h1('Hello World'),
              $q->end_html;

        $c->restore;

        my $response = $c->response;

        # to prevent blocking problems in single threaded daemon.
        $response->header( Connection => 'close' );

        $client->send_response($response);
    }

    $client->close;
}
