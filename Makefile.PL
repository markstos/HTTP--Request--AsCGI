#!perl

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'HTTP::Request::AsCGI',
    VERSION_FROM => 'lib/HTTP/Request/AsCGI.pm',
    PREREQ_PM    => {
        Carp             => 0,
        Class::Accessor  => 0,
        File::Temp       => 0.14,
        IO::Handle       => 0
    }
);
