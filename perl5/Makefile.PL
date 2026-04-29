use 5.020;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'VOF',
    VERSION_FROM     => 'lib/VOF.pm',
    ABSTRACT         => 'Vanilla Object Framework - JSON client library',
    AUTHOR           => 'Stéphane Lavergne <https://github.com/vphantom>',
    LICENSE          => 'mit',
    MIN_PERL_VERSION => '5.020',
    PREREQ_PM        => {
        'JSON'         => '2.90',
        'MIME::Base64' => '3.13',
    },
    TEST_REQUIRES    => {
        'Test::More'  => '0.96',
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/vphantom/vof.git',
                web  => 'https://github.com/vphantom/vof',
            },
        },
    },
);
