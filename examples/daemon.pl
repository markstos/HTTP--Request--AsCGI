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

        my $c = HTTP::Request::AsCGI->new( $request, %e )->setup;
        my $q = CGI->new;

        print $q->header,
              $q->start_html('Hello World'),
              $q->h1('Hello World'),
              $q->end_html;

        $c->restore;

        my $message = "HTTP/1.1 200\x0d\x0a";

        while ( my $line = $c->stdout->getline ) {
            $message .= $line;
            last if $line =~ /^\x0d?\x0a$/;
        }

        my $response = HTTP::Response->parse($message);

        if ( my $code = $response->header('Status') ) {
            $response->code($code);
        }

        $response->header( Connection => 'close' );
        $response->protocol( $request->protocol );
        $response->content( sub {
            if ( $c->stdout->read( my $buffer, 4096 ) ) {
                return $buffer;
            }
            return undef;
        });

        $client->send_response($response);
        $client->close;
    }

    #$client->close;
}
