package HTTP::Request::AsCGI;

use strict;
use warnings;
use bytes;
use base 'Class::Accessor::Fast';

use Carp;
use IO::File;

__PACKAGE__->mk_accessors(qw[ enviroment request stdin stdout stderr ]);

our $VERSION = 0.1;

sub new {
    my $class   = shift;
    my $request = shift;

    my $self = {
        request  => $request,
        restored => 0,
        setuped  => 0,
        stdin    => IO::File->new_tmpfile,
        stdout   => IO::File->new_tmpfile,
        stderr   => IO::File->new_tmpfile
    };

    $self->{enviroment} = {
        GATEWAY_INTERFACE => 'CGI/1.1',
        HTTP_HOST         => $request->uri->host_port,
        PATH_INFO         => $request->uri->path,
        QUERY_STRING      => $request->uri->query || '',
        SCRIPT_NAME       => '/',
        SERVER_NAME       => $request->uri->host,
        SERVER_PORT       => $request->uri->port,
        SERVER_PROTOCOL   => $request->protocol || 'HTTP/1.1',
        SERVER_SOFTWARE   => __PACKAGE__ . "/" . $VERSION,
        REMOTE_ADDR       => '127.0.0.1',
        REMOTE_HOST       => 'localhost',
        REMOTE_PORT       => int( rand(64000) + 1000 ),        # not in RFC 3875
        REQUEST_URI       => $request->uri->path || '/',       # not in RFC 3875
        REQUEST_METHOD    => $request->method,
        @_
    };

    foreach my $field ( $request->headers->header_field_names ) {

        my $key = uc($field);
        $key =~ tr/-/_/;
        $key = 'HTTP_' . $key unless $field =~ /^Content-(Length|Type)$/;

        unless ( exists $self->{enviroment}->{$key} ) {
            $self->{enviroment}->{$key} = $request->headers->header($field);
        }
    }

    return $class->SUPER::new($self);
}

sub setup {
    my $self = shift;

    $self->{restore}->{enviroment} = {%ENV};

    open( $self->{restore}->{stdin}, '>&', STDIN->fileno )
      or croak("Can't dup stdin: $!");

    open( STDIN, '<&=', $self->stdin->fileno )
      or croak("Can't open stdin: $!");
      
    binmode( STDIN, ':raw' );

    if ( $self->request->content_length ) {

        $self->stdin->syswrite( $self->request->content )
          or croak("Can't write request content to stdin handle: $!");

        $self->stdin->sysseek( 0, SEEK_SET )
          or croak("Can't seek stdin handle: $!");
    }

    if ( $self->stdout ) {
        open( $self->{restore}->{stdout}, '>&', STDOUT->fileno )
          or croak("Can't dup stdout: $!");

        open( STDOUT, '>&=', $self->stdout->fileno )
          or croak("Can't open stdout: $!");
          
        binmode( STDOUT, ':raw' );
    }

    if ( $self->stderr ) {
        open( $self->{restore}->{stderr}, '>&', STDERR->fileno )
          or croak("Can't dup stderr: $!");

        open( STDERR, '>&=', $self->stderr->fileno )
          or croak("Can't open stderr: $!");
        
        binmode( STDERR, ':raw' );
    }

    {
        no warnings 'uninitialized';
        %ENV = %{ $self->enviroment };
    }

    $self->{setuped}++;

    return $self;
}

sub response {
    my ( $self, $callback ) = @_;

    return undef unless $self->{setuped};
    return undef unless $self->{restored};
    return undef unless $self->{restore}->{stdout};

    require HTTP::Response;

    my $message  = undef;
    my $position = $self->stdin->tell;

    $self->stdout->sysseek( 0, SEEK_SET )
      or croak("Can't seek stdin handle: $!");

    while ( my $line = $self->stdout->getline ) {
        $message .= $line;
        last if $line =~ /^\x0d?\x0a$/;
    }

    unless ( $message =~ /^HTTP/ ) {
        $message = "HTTP/1.1 200\x0d\x0a" . $message;
    }

    my $response = HTTP::Response->parse($message);

    if ( my $code = $response->header('Status') ) {
        $response->code($code);
    }

    $response->protocol( $self->request->protocol );
    $response->headers->date( time() );

    if ($callback) {
        $response->content( sub {
            if ( $self->stdout->read( my $buffer, 4096 ) ) {
                return $buffer;
            }
            return undef;
        });
    }
    else {
        my $length = 0;
        while ( $self->stdout->read( my $buffer, 4096 ) ) {
            $length += length($buffer);
            $response->add_content($buffer);
        }
        $response->content_length($length) unless $response->content_length;
    }

    $self->stdout->sysseek( $position, SEEK_SET )
      or croak("Can't seek stdin handle: $!");

    return $response;
}

sub restore {
    my $self = shift;

    %ENV = %{ $self->{restore}->{enviroment} };

    open( STDIN, '>&', $self->{restore}->{stdin} )
      or croak("Can't restore stdin: $!");

    $self->stdin->sysseek( 0, SEEK_SET )
      or croak("Can't seek stdin: $!");

    if ( $self->{restore}->{stdout} ) {
        open( STDOUT, '>&', $self->{restore}->{stdout} )
          or croak("Can't restore stdout: $!");

        $self->stdout->sysseek( 0, SEEK_SET )
          or croak("Can't seek stdout: $!");
    }

    if ( $self->{restore}->{stderr} ) {
        open( STDERR, '>&', $self->{restore}->{stderr} )
          or croak("Can't restore stderr: $!");

        $self->stderr->sysseek( 0, SEEK_SET )
          or croak("Can't seek stderr: $!");
    }

    $self->{restored}++;

    return $self;
}

sub DESTROY {
    my $self = shift;
    $self->restore if $self->{setuped} && !$self->{restored};
}

1;

__END__

=head1 NAME

HTTP::Request::AsCGI - Setup a CGI enviroment from a HTTP::Request

=head1 SYNOPSIS

    use CGI;
    use HTTP::Request;
    use HTTP::Request::AsCGI;
    
    my $request = HTTP::Request->new( GET => 'http://www.host.com/' );
    my $stdout;
    
    {
        my $c = HTTP::Request::AsCGI->new($request)->setup;
        my $q = CGI->new;
        
        print $q->header,
              $q->start_html('Hello World'),
              $q->h1('Hello World'),
              $q->end_html;
        
        $stdout = $c->stdout;
        
        # enviroment and descriptors will automatically be restored when $c is destructed.
    }
    
    while ( my $line = $stdout->getline ) {
        print $line;
    }
    
=head1 DESCRIPTION

=head1 METHODS

=over 4 

=item new

=item enviroment

=item setup

=item restore

=item request

=item response

=item stdin

=item stdout

=item stderr

=back

=head1 BUGS

=head1 AUTHOR

Christian Hansen, C<ch@ngmedia.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify 
it under the same terms as perl itself.

=cut
