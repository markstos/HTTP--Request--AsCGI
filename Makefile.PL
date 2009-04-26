#!perl

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'HTTP::Request::AsCGI',
    VERSION_FROM => 'lib/HTTP/Request/AsCGI.pm',
    PREREQ_PM    => {
        Carp             => 0,
        Class::Accessor  => 0,        
        HTTP::Request    => 0,
        HTTP::Response   => 1.53,
        IO::File         => 0,
        Test::More       => 0
    }
);
