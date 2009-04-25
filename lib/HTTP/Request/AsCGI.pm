package HTTP::Request::AsCGI;

use strict;
use warnings;
use bytes;
use base 'Class::Accessor::Fast';

use Carp            qw[croak];
use HTTP::Response  qw[];
use IO::File        qw[SEEK_SET];
use Symbol          qw[];
use URI::Escape     qw[];

__PACKAGE__->mk_accessors( qw[ is_setup
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

our $VERSION = 0.5_01;

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
        $self->environment( { %{ $params->{environment} } } );
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

my $HTTP_Token   = qr/[\x21\x23-\x27\x2A\x2B\x2D\x2E\x30-\x39\x41-\x5A\x5E-\x7A\x7C\x7E]/;
my $HTTP_Version = qr/HTTP\/[0-9]+\.[0-9]+/;

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
        PATH_INFO         => URI::Escape::uri_unescape($uri->path),
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

    if ( my $authorization = $request->header('Authorization') ) {

        ( my $scheme ) = $authorization =~ /^($HTTP_Token+)/o;

        if ( $scheme =~ /^Basic/i ) {

            if ( ( my $username ) = $request->headers->authorization_basic ) {
                $cgi{AUTH_TYPE}   = 'Basic';
                $cgi{REMOTE_USER} = $username;
            }
        }
        elsif ( $scheme =~ /^Digest/i ) {

            if ( ( my $username ) = $authorization =~ /username="([^"]+)"/ ) {
                $cgi{AUTH_TYPE}   = 'Digest';
                $cgi{REMOTE_USER} = $username;
            }
        }
    }

    foreach my $key ( keys %cgi ) {

        unless ( exists $environment->{ $key } ) {
            $environment->{ $key } = $cgi{ $key };
        }
    }

    foreach my $field ( $request->headers->header_field_names ) {

        my $key = uc("HTTP_$field");
        $key =~ tr/-/_/;
        $key =~ s/^HTTP_// if $field =~ /^Content-(Length|Type)$/;

        unless ( exists $environment->{ $key } ) {
            $environment->{ $key } = $request->headers->header($field);
        }
    }

    if ( $environment->{SCRIPT_NAME} ne '/' && $environment->{PATH_INFO} ) {
        $environment->{PATH_INFO} =~ s/^\Q$environment->{SCRIPT_NAME}\E/\//;
        $environment->{PATH_INFO} =~ s/^\/+/\//;
    }

    $self->is_prepared(1);
}

sub setup {
    my $self = shift;

    if ( $self->is_setup ) {
        croak(   'An attempt was made to setup environment variables and '
               . 'standard filehandles which has already been setup.' );
    }

    if ( $self->should_setup_content && $self->has_stdin ) {
        $self->setup_content;
    }

    if ( $self->has_stdin ) {

        if ( $self->should_dup ) {

            if ( $self->should_restore ) {

                open( my $stdin, '<&STDIN' )
                  or croak("Couldn't dup STDIN: '$!'");

                $self->{restore}->{stdin} = $stdin;
            }

            open( STDIN, '<&' . fileno($self->stdin) )
              or croak("Couldn't dup stdin filehandle to STDIN: '$!'");
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

    if ( $self->has_stdout ) {

        if ( $self->should_dup ) {

            if ( $self->should_restore ) {

                open( my $stdout, '>&STDOUT' )
                  or croak("Couldn't dup STDOUT: '$!'");

                $self->{restore}->{stdout} = $stdout;
            }

            open( STDOUT, '>&' . fileno($self->stdout) )
              or croak("Couldn't dup stdout filehandle to STDOUT: '$!'");
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

    if ( $self->has_stderr ) {

        if ( $self->should_dup ) {

            if ( $self->should_restore ) {

                open( my $stderr, '>&STDERR' )
                  or croak("Couldn't dup STDERR: '$!'");

                $self->{restore}->{stderr} = $stderr;
            }

            open( STDERR, '>&' . fileno($self->stderr) )
              or croak("Couldn't dup stdout filehandle to STDOUT: '$!'");
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

    {
        no warnings 'uninitialized';

        if ( $self->should_restore ) {
            $self->{restore}->{environment} = { %ENV };
        }

        %ENV = %{ $self->environment };
    }

    if ( $INC{'CGI.pm'} ) {
        CGI::initialize_globals();
    }

    $self->is_setup(1);

    return $self;
}

sub setup_content {
    my $self  = shift;
    my $stdin = shift || $self->stdin;

    my $content = $self->request->content_ref;

    if ( ref($content) eq 'SCALAR' ) {

        if ( defined($$content) && length($$content) ) {

            print( { $stdin } $$content )
              or croak("Couldn't write request content SCALAR to stdin filehandle: '$!'");

            if ( $self->should_rewind ) {

                seek( $stdin, 0, SEEK_SET )
                  or croak("Couldn't rewind stdin filehandle: '$!'");
            }
        }
    }
    elsif ( ref($content) eq 'CODE' ) {

        while () {

            my $chunk = &$content();

            if ( defined($chunk) && length($chunk) ) {

                print( { $stdin } $chunk )
                  or croak("Couldn't write request content callback to stdin filehandle: '$!'");
            }
            else {
                last;
            }
        }

        if ( $self->should_rewind ) {

            seek( $stdin, 0, SEEK_SET )
              or croak("Couldn't rewind stdin filehandle: '$!'");
        }
    }
    else {
        croak("Couldn't write request content to stdin filehandle: 'Unknown request content $content'");
    }
}

sub response {
    my $self   = shift;
    my %params = ( headers_only => 0, sync => 0, @_ );

    return undef unless $self->has_stdout;

    if ( $self->should_rewind ) {

        seek( $self->stdout, 0, SEEK_SET )
          or croak("Couldn't rewind stdout filehandle: '$!'");
    }

    my $message  = undef;
    my $response = HTTP::Response->new( 200, 'OK' );
       $response->protocol('HTTP/1.1');

    while ( my $line = readline($self->stdout) ) {

        if ( !$message && $line =~ /^\x0d?\x0a$/ ) {
            next;
        }
        else {
            $message .= $line;
        }

        last if $message =~ /\x0d?\x0a\x0d?\x0a$/;
    }

    if ( !$message ) {
        $response->code(500);
        $response->message('Internal Server Error');
        $response->date( time() );
        $response->content( $response->error_as_HTML );
        $response->content_type('text/html');
        $response->content_length( length $response->content );

        return $response;
    }

    if ( $message =~ s/^($HTTP_Version)[\x09\x20]+(\d\d\d)[\x09\x20]+([\x20-\xFF]*)\x0D?\x0A//o ) {
        $response->protocol($1);
        $response->code($2);
        $response->message($3);
    }

    $message =~ s/\x0D?\x0A[\x09\x20]+/\x20/gs;

    foreach ( split /\x0D?\x0A/, $message ) {

        s/[\x09\x20]*$//;

        if ( /^($HTTP_Token+)[\x09\x20]*:[\x09\x20]*([\x20-\xFF]+)$/o ) {
            $response->headers->push_header( $1 => $2 );
        }
        else {
            # XXX what should we do on bad headers?
        }
    }

    my $status = $response->header('Status');

    if ( $status && $status =~ /^(\d\d\d)[\x09\x20]+([\x20-\xFF]+)$/ ) {
        $response->code($1);
        $response->message($2);
    }

    if ( !$response->date ) {
        $response->date(time());
    }

    if ( $params{headers_only} ) {

        if ( $params{sync} ) {

            my $position = tell( $self->stdout )
              or croak("Couldn't get file position from stdout filehandle: '$!'");

            sysseek( $self->stdout, $position, SEEK_SET )
              or croak("Couldn't seek stdout filehandle: '$!'");
        }

        return $response;
    }

    my $content        = undef;
    my $content_length = 0;

    while () {

        my $r = read( $self->stdout, $content, 65536, $content_length );

        if ( defined $r ) {

            if ( $r == 0 ) {
                last;
            }
            else {
                $content_length += $r;
            }
        }
        else {
            croak("Couldn't read response content from stdin filehandle: '$!'");
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

    if ( !$self->should_restore ) {
        croak(   'An attempt was made to restore environment variables and '
               . 'standard filehandles which has not been saved.' );
    }

    if ( !$self->is_setup ) {
        croak(   'An attempt was made to restore environment variables and '
               . 'standard filehandles which has not been setup.' );
    }

    if ( $self->is_restored ) {
        croak(   'An attempt was made to restore environment variables and '
               . 'standard filehandles which has already been restored.' );
    }

    {
        no warnings 'uninitialized';
        %ENV = %{ $self->{restore}->{environment} };
    }

    if ( $self->has_stdin ) {

        my $stdin = $self->{restore}->{stdin};

        if ( $self->should_dup ) {

            STDIN->fdopen( fileno($stdin), '<' )
              or croak("Couldn't restore STDIN: '$!'");
        }
        else {

            my $stdin_ref = $self->{restore}->{stdin_ref};
              *$stdin_ref = $stdin;
        }

        if ( $self->should_rewind ) {

            seek( $self->stdin, 0, SEEK_SET )
              or croak("Couldn't rewind stdin filehandle: '$!'");
        }
    }

    if ( $self->has_stdout ) {

        my $stdout = $self->{restore}->{stdout};

        if ( $self->should_dup ) {

            STDOUT->flush
              or croak("Couldn't flush STDOUT: '$!'");

            STDOUT->fdopen( fileno($stdout), '>' )
              or croak("Couldn't restore STDOUT: '$!'");
        }
        else {

            my $stdout_ref = $self->{restore}->{stdout_ref};
              *$stdout_ref = $stdout;
        }

        if ( $self->should_rewind ) {

            seek( $self->stdout, 0, SEEK_SET )
              or croak("Couldn't rewind stdout filehandle: '$!'");
        }
    }

    if ( $self->has_stderr ) {

        my $stderr = $self->{restore}->{stderr};

        if ( $self->should_dup ) {

            STDERR->flush
              or croak("Couldn't flush STDERR: '$!'");

            STDERR->fdopen( fileno($stderr), '>' )
              or croak("Couldn't restore STDERR: '$!'");
        }
        else {

            my $stderr_ref = $self->{restore}->{stderr_ref};
              *$stderr_ref = $stderr;
        }

        if ( $self->should_rewind ) {

            seek( $self->stderr, 0, SEEK_SET )
              or croak("Couldn't rewind stderr filehandle: '$!'");
        }
    }

    $self->{restore} = {};

    $self->is_restored(1);

    return $self;
}

sub DESTROY {
    my $self = shift;

    if ( $self->should_restore && $self->is_setup && !$self->is_restored ) {
        $self->restore;
    }
}

1;

__END__

=head1 NAME

HTTP::Request::AsCGI - Setup a Common Gateway Interface environment from a HTTP::Request

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

        # environment and descriptors is automatically restored
        # when $c is destructed.
    }

    while ( my $line = $stdout->getline ) {
        print $line;
    }

=head1 DESCRIPTION

Provides a convinient way of setting up an CGI environment from a HTTP::Request.

=head1 METHODS

=over 4

=item * new

Constructor, this method takes a hash of parameters. The following parameters are
valid:

=over 8

=item * request

    request => HTTP::Request->new( GET => 'http://www.host.com/' )

=item * stdin

A filehandle to be used as standard input, defaults to a temporary filehandle.
If C<stdin> is C<undef>, standard input will be left as is.

    stdin => IO::File->new_tmpfile
    stdin => IO::String->new
    stdin => $fh
    stdin => undef

=item * stdout

A filehandle to be used as standard output, defaults to a temporary filehandle.
If C<stdout> is C<undef>, standard output will be left as is.

    stdout => IO::File->new_tmpfile
    stdout => IO::String->new
    stdout => $fh
    stdout => undef

=item * stderr

A filehandle to be used as standard error, defaults to C<undef>. If C<stderr> is
C<undef>, standard error will be left as is.

    stderr => IO::File->new_tmpfile
    stderr => IO::String->new
    stderr => $fh
    stderr => undef

=item * environment

A C<HASH> of additional environment variables to be used in CGI.
C<HTTP::Request::AsCGI> doesn't autmatically merge C<%ENV>, it has to be
explicitly given if that is desired. Environment variables given in this
C<HASH> isn't overridden by C<HTTP::Request::AsCGI>.

    environment => \%ENV
    environment => { PATH => '/bin:/usr/bin', SERVER_SOFTWARE => 'Apache/1.3' }

Following standard meta-variables (in addition to protocol-specific) is setup:

    AUTH_TYPE
    CONTENT_LENGTH
    CONTENT_TYPE
    GATEWAY_INTERFACE
    PATH_INFO
    SCRIPT_NAME
    SERVER_NAME
    SERVER_PORT
    SERVER_PROTOCOL
    SERVER_SOFTWARE
    REMOTE_ADDR
    REMOTE_HOST
    REMOTE_USER
    REQUEST_METHOD
    QUERY_STRING

Following non-standard but common meta-variables is setup:

    HTTPS
    REMOTE_PORT
    REQUEST_URI

Following meta-variables is B<not> setup but B<must> be provided in CGI:

    PATH_TRANSLATED

Following meta-variables is B<not> setup but common in CGI:

    DOCUMENT_ROOT
    SCRIPT_FILENAME
    SERVER_ROOT

=item * dup

Boolean to indicate whether to C<dup> standard filehandle or to assign the
typeglob representing the standard filehandle. Defaults to C<true>.

    dup => 0
    dup => 1

=item * restore

Boolean to indicate whether or not to restore environment variables and standard
filehandles. Defaults to C<true>.

    restore => 0
    restore => 1

If C<true> standard filehandles and environment variables will be saved duiring
C<setup> for later use in C<restore>.

=item * rewind

Boolean to indicate whether or not to rewind standard filehandles. Defaults
to C<true>.

    rewind => 0
    rewind => 1

=item * content

Boolean to indicate whether or not to request content should be written to
C<stdin> filehandle when C<setup> is invoked. Defaults to C<true>.

    content => 0
    content => 1

=back

=item * setup

Attempts to setup standard filehandles and environment variables.

=item * restore

Attempts to restore standard filehandles and environment variables.

=item * response

Attempts to parse C<stdout> filehandle into a L<HTTP::Response>.

=item * request

Accessor for L<HTTP::Request> that was given to constructor.

=item * environment

Accessor for environment variables to be used in C<setup>.

=item * stdin

Accessor/Mutator for standard input filehandle.

=item * stdout

Accessor/Mutator for standard output filehandle.

=item * stderr

Accessor/Mutator for standard error filehandle.

=back

=head1 DEPRECATED

XXX Constructor

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
