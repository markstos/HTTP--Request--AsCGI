package HTTP::Request::AsCGI;

use strict;
use warnings;
use bytes;
use base 'Class::Accessor::Fast';

use Carp            qw[croak];
use HTTP::Response  qw[];
use IO::Handle      qw[];
use IO::File        qw[SEEK_SET];
use Symbol          qw[];

__PACKAGE__->mk_accessors( qw[ is_setuped
                               is_prepared
                               is_restored

                               should_dup
                               should_restore
                               should_rewind
                               should_setup_content

                               environment
                               request
                               stdin
                               stdout
                               stderr ] );

our $VERSION = 0.6_01;

sub new {
    my $class  = ref $_[0] ? ref shift : shift;
    my $params = {};

    if ( @_ % 2 == 0 ) {
        $params = { @_ };
    }
    else {
        $params = { request => shift, environment => { @_ } };
    }

    return bless( {}, $class )->initialize($params);
}

sub initialize {
    my ( $self, $params ) = @_;

    if ( exists $params->{request} ) {
        $self->request( $params->{request} );
    }
    else {
        croak("Mandatory parameter 'request' is missing.");
    }

    if ( exists $params->{environment} ) {
        $self->environment( $params->{environment} );
    }
    else {
        $self->environment( {} );
    }

    if ( exists $params->{stdin} ) {
        $self->stdin( $params->{stdin} );
    }
    else {
        $self->stdin( IO::File->new_tmpfile );
    }

    if ( exists $params->{stdout} ) {
        $self->stdout( $params->{stdout} );
    }
    else {
        $self->stdout( IO::File->new_tmpfile );
    }

    if ( exists $params->{stderr} ) {
        $self->stderr( $params->{stderr} );
    }

    if ( exists $params->{dup} ) {
        $self->should_dup( $params->{dup} ? 1 : 0 );
    }
    else {
        $self->should_dup(1);
    }

    if ( exists $params->{restore} ) {
        $self->should_restore( $params->{restore} ? 1 : 0 );
    }
    else {
        $self->should_restore(1);
    }

    if ( exists $params->{rewind} ) {
        $self->should_rewind( $params->{rewind} ? 1 : 0 );
    }
    else {
        $self->should_rewind(1);
    }

    if ( exists $params->{content} ) {
        $self->should_setup_content( $params->{content} ? 1 : 0 );
    }
    else {
        $self->should_setup_content(1);
    }

    $self->prepare;

    return $self;
}

*enviroment = \&environment;

sub has_stdin  { return defined $_[0]->stdin  }
sub has_stdout { return defined $_[0]->stdout }
sub has_stderr { return defined $_[0]->stderr }

sub prepare {
    my $self = shift;

    my $environment = $self->environment;
    my $request     = $self->request;

    my $host = $request->header('Host');
    my $uri  = $request->uri->clone;

    $uri->scheme('http')    unless $uri->scheme;
    $uri->host('localhost') unless $uri->host;
    $uri->port(80)          unless $uri->port;
    $uri->host_port($host)  unless !$host || ( $host eq $uri->host_port );

    $uri = $uri->canonical;

    my %cgi = (
        GATEWAY_INTERFACE => 'CGI/1.1',
        HTTP_HOST         => $uri->host_port,
        HTTPS             => ( $uri->scheme eq 'https' ) ? 'ON' : 'OFF',  # not in RFC 3875
        PATH_INFO         => $uri->path,
        QUERY_STRING      => $uri->query || '',
        SCRIPT_NAME       => '/',
        SERVER_NAME       => $uri->host,
        SERVER_PORT       => $uri->port,
        SERVER_PROTOCOL   => $request->protocol || 'HTTP/1.1',
        SERVER_SOFTWARE   => "HTTP-Request-AsCGI/$VERSION",
        REMOTE_ADDR       => '127.0.0.1',
        REMOTE_HOST       => 'localhost',
        REMOTE_PORT       => int( rand(64000) + 1000 ),                   # not in RFC 3875
        REQUEST_URI       => $uri->path_query,                            # not in RFC 3875
        REQUEST_METHOD    => $request->method
    );

    foreach my $key ( keys %cgi ) {

        unless ( exists $environment->{ $key } ) {
            $environment->{ $key } = $cgi{ $key };
        }
    }

    foreach my $field ( $self->request->headers->header_field_names ) {

        my $key = uc("HTTP_$field");
        $key =~ tr/-/_/;
        $key =~ s/^HTTP_// if $field =~ /^Content-(Length|Type)$/;

        unless ( exists $environment->{ $key } ) {
            $environment->{ $key } = $self->request->headers->header($field);
        }
    }

    unless ( $environment->{SCRIPT_NAME} eq '/' && $environment->{PATH_INFO} ) {
        $environment->{PATH_INFO} =~ s/^\Q$environment->{SCRIPT_NAME}\E/\//;
        $environment->{PATH_INFO} =~ s/^\/+/\//;
    }

    $self->is_prepared(1);
}

sub setup {
    my $self = shift;

    $self->setup_content;
    $self->setup_stdin;
    $self->setup_stdout;
    $self->setup_stderr;
    $self->setup_environment;

    if ( $INC{'CGI.pm'} ) {
        CGI::initialize_globals();
    }

    $self->is_setuped(1);

    return $self;
}

sub setup_content {
    my $self = shift;

    if ( $self->should_setup_content && $self->has_stdin ) {

        if ( $self->request->content_length ) {

            my $content = $self->request->content_ref;

            if ( ref $content eq 'SCALAR' ) {

                if ( defined $$content && length $$content ) {

                    print( { $self->stdin } $$content )
                      or croak("Couldn't write request content to stdin handle: '$!'");

                    if ( $self->should_rewind ) {

                        seek( $self->stdin, 0, SEEK_SET )
                          or croak("Couldn't seek stdin handle: '$!'");
                    }
                }
            }
            else {
                croak("Can't handle request content of '$content'");
            }
        }
    }
}

sub setup_stdin {
    my $self = shift;

    if ( $self->has_stdin ) {

        if ( $self->should_dup ) {

            if ( $self->should_restore ) {

                open( my $stdin, '<&STDIN' )
                  or croak("Couldn't dup STDIN: '$!'");

                $self->{restore}->{stdin} = $stdin;
            }

            STDIN->fdopen( $self->stdin, '<' )
              or croak("Couldn't dup stdin handle to STDIN: '$!'");
        }
        else {

            my $stdin = Symbol::qualify_to_ref('STDIN');

            if ( $self->should_restore ) {

                $self->{restore}->{stdin}     = *$stdin;
                $self->{restore}->{stdin_ref} = \*$stdin;
            }

            *$stdin = $self->stdin;
        }

        binmode( $self->stdin );
        binmode( STDIN );
    }
}

sub setup_stdout {
    my $self = shift;

    if ( $self->has_stdout ) {

        if ( $self->should_dup ) {

            if ( $self->should_restore ) {

                open( my $stdout, '>&STDOUT' )
                  or croak("Couldn't dup STDOUT: '$!'");

                $self->{restore}->{stdout} = $stdout;
            }

            STDOUT->fdopen( $self->stdout, '>' )
              or croak("Couldn't dup stdout handle to STDOUT: '$!'");
        }
        else {

            my $stdout = Symbol::qualify_to_ref('STDOUT');

            if ( $self->should_restore ) {

                $self->{restore}->{stdout}     = *$stdout;
                $self->{restore}->{stdout_ref} = \*$stdout;
            }

            *$stdout = $self->stdout;
        }

        binmode( $self->stdout );
        binmode( STDOUT);
    }
}

sub setup_stderr {
    my $self = shift;

    if ( $self->has_stderr ) {

        if ( $self->should_dup ) {

            if ( $self->should_restore ) {

                open( my $stderr, '>&STDERR' )
                  or croak("Couldn't dup STDERR: '$!'");

                $self->{restore}->{stderr} = $stderr;
            }

            STDERR->fdopen( $self->stderr, '>' )
              or croak("Couldn't dup stderr handle to STDERR: '$!'");
        }
        else {

            my $stderr = Symbol::qualify_to_ref('STDERR');

            if ( $self->should_restore ) {

                $self->{restore}->{stderr}     = *$stderr;
                $self->{restore}->{stderr_ref} = \*$stderr;
            }

            *$stderr = $self->stderr;
        }

        binmode( $self->stderr );
        binmode( STDERR );
    }
}

sub setup_environment {
    my $self = shift;

    no warnings 'uninitialized';

    if ( $self->should_restore ) {
        $self->{restore}->{environment} = { %ENV };
    }

    %ENV = %{ $self->environment };
}

sub response {
    my $self   = shift;
    my %params = ( headers_only => 0, sync => 0, @_ );

    return undef unless $self->has_stdout;

    if ( $self->should_rewind ) {

        seek( $self->stdout, 0, SEEK_SET )
          or croak("Couldn't seek stdout handle: '$!'");
    }

    my $message  = undef;
    my $response = HTTP::Response->new( 200, 'OK' );
       $response->protocol('HTTP/1.1');

    while ( my $line = $self->stdout->getline ) {
        $message .= $line;
        last if $message =~ /\x0d?\x0a\x0d?\x0a$/;
    }

    if ( !$message ) {

        $response->code(500);
        $response->message('Internal Server Error');
        $response->date( time );
        $response->content( $response->error_as_HTML );
        $response->content_type('text/html');
        $response->content_length( length $response->content );

        return $response;
    }

    my $Token   = qr/[\x21\x23-\x27\x2A\x2B\x2D\x2E\x30-\x39\x41-\x5A\x5E-\x7A\x7C\x7E]/;
    my $Version = qr/HTTP\/[0-9]+\.[0-9]+/;

    if ( $message =~ s/^($Version)[\x09\x20]+(\d{3})[\x09\x20]+([\x20-\xFF]*)\x0D?\x0A//o ) {

        $response->protocol($1);
        $response->code($2);
        $response->message($3);
    }

    $message =~ s/\x0D?\x0A[\x09\x20]+/\x20/gs;

    foreach ( split /\x0D?\x0A/, $message ) {

        if ( /^($Token+)[\x09\x20]*:[\x09\x20]*([\x20-\xFF]+)[\x09\x20]*$/o ) {
            $response->headers->push_header( $1 => $2 );
        }
        else {
            # XXX what should we do on bad headers?
        }
    }

    my $status = $response->header('Status');

    if ( $status && $status =~ /^(\d{3})[\x09\x20]+([\x20-\xFF]+)$/ ) {
        $response->code($1);
        $response->message($2);
    }

    if ( !$response->date ) {
        $response->date(time);
    }

    if ( $params{headers_only} ) {

        if ( $params{sync} ) {

            my $position = tell( $self->stdout )
              or croak("Couldn't get file position from stdout handle: '$!'");

            sysseek( $self->stdout, $position, SEEK_SET )
              or croak("Couldn't seek stdout handle: '$!'");
        }

        return $response;
    }

    my $content        = undef;
    my $content_length = 0;

    while () {

        my $r = $self->stdout->read( $content, 65536, $content_length );

        if ( defined $r ) {

            $content_length += $r;

            last unless $r;
        }
        else {
            croak("Couldn't read response content from stdin handle: '$!'");
        }
    }

    if ( $content_length ) {

        $response->content_ref(\$content);

        if ( !$response->content_length ) {
            $response->content_length($content_length);
        }
    }

    return $response;
}

sub restore {
    my $self = shift;

    if ( $self->should_restore ) {

        $self->restore_environment;
        $self->restore_stdin;
        $self->restore_stdout;
        $self->restore_stderr;

        $self->{restore} = {};

        $self->is_restored(1);
    }

    return $self;
}

sub restore_environment {
    my $self = shift;

    no warnings 'uninitialized';

    %ENV = %{ $self->{restore}->{environment} };
}

sub restore_stdin {
    my $self = shift;

    if ( $self->has_stdin ) {

        my $stdin = $self->{restore}->{stdin};

        if ( $self->should_dup ) {

            STDIN->fdopen( $stdin, '<' )
              or croak("Couldn't restore STDIN: '$!'");
        }
        else {

            my $stdin_ref = $self->{restore}->{stdin_ref};
              *$stdin_ref = $stdin;
        }

        if ( $self->should_rewind ) {

            seek( $self->stdin, 0, SEEK_SET )
              or croak("Couldn't seek stdin handle: '$!'");
        }
    }
}

sub restore_stdout {
    my $self = shift;

    if ( $self->has_stdout ) {

        my $stdout = $self->{restore}->{stdout};

        if ( $self->should_dup ) {

            STDOUT->flush
              or croak("Couldn't flush STDOUT: '$!'");

            STDOUT->fdopen( $stdout, '>' )
              or croak("Couldn't restore STDOUT: '$!'");
        }
        else {

            my $stdout_ref = $self->{restore}->{stdout_ref};
              *$stdout_ref = $stdout;
        }

        if ( $self->should_rewind ) {

            seek( $self->stdout, 0, SEEK_SET )
              or croak("Couldn't seek stdout handle: '$!'");
        }
    }
}

sub restore_stderr {
    my $self = shift;

    if ( $self->has_stderr ) {

        my $stderr = $self->{restore}->{stderr};

        if ( $self->should_dup ) {

            STDERR->flush
              or croak("Couldn't flush STDERR: '$!'");

            STDERR->fdopen( $stderr, '>' )
              or croak("Couldn't restore STDERR: '$!'");
        }
        else {

            my $stderr_ref = $self->{restore}->{stderr_ref};
              *$stderr_ref = $stderr;
        }

        if ( $self->should_rewind ) {

            seek( $self->stderr, 0, SEEK_SET )
              or croak("Couldn't seek stderr handle: '$!'");
        }
    }
}

sub DESTROY {
    my $self = shift;

    if ( $self->should_restore && $self->is_setuped && !$self->is_restored ) {
        $self->restore;
    }
}

1;

__END__

=head1 NAME

HTTP::Request::AsCGI - Setup a CGI environment from a HTTP::Request

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

        # environment and descriptors will automatically be restored
        # when $c is destructed.
    }

    while ( my $line = $stdout->getline ) {
        print $line;
    }

=head1 DESCRIPTION

Provides a convinient way of setting up an CGI environment from a HTTP::Request.

=head1 METHODS

=over 4

=item new ( $request [, key => value ] )

Contructor, first argument must be a instance of HTTP::Request
followed by optional pairs of environment key and value.

=item environment

Returns a hashref containing the environment that will be used in setup.
Changing the hashref after setup has been called will have no effect.

=item setup

Setups the environment and descriptors.

=item restore

Restores the environment and descriptors. Can only be called after setup.

=item request

Returns the request given to constructor.

=item response

Returns a HTTP::Response. Can only be called after restore.

=item stdin

Accessor for handle that will be used for STDIN, must be a real seekable
handle with an file descriptor. Defaults to a tempoary IO::File instance.

=item stdout

Accessor for handle that will be used for STDOUT, must be a real seekable
handle with an file descriptor. Defaults to a tempoary IO::File instance.

=item stderr

Accessor for handle that will be used for STDERR, must be a real seekable
handle with an file descriptor.

=back

=head1 SEE ALSO

=over 4

=item examples directory in this distribution.

=item L<WWW::Mechanize::CGI>

=item L<Test::WWW::Mechanize::CGI>

=back

=head1 THANKS TO

Thomas L. Shinnick for his valuable win32 testing.

=head1 AUTHOR

Christian Hansen, C<ch@ngmedia.com>

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as perl itself.

=cut
