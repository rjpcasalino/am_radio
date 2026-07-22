use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'AmRadio',
    VERSION_FROM     => 'lib/AmRadio/Config.pm',
    ABSTRACT         => 'Command-line internet radio player with optional TUI',
    AUTHOR           => 'am_radio contributors',
    LICENSE          => 'perl_5',
    MIN_PERL_VERSION => '5.014',
    PREREQ_PM        => {
        'strict'           => 0,
        'warnings'         => 0,
        'File::Basename'   => 0,
        'Getopt::Long'     => '2.33',
        'JSON::PP'         => '2.27',
        'IO::Socket::UNIX' => 0,
        'IO::Select'       => 0,
        'POSIX'            => 0,
        'Time::HiRes'      => 0,
        'Encode'           => 0,
    },
    TEST_REQUIRES    => {
        'Test::More' => '0.96',
    },
    test             => { TESTS => 't/*.t' },
    EXE_FILES        => ['am_radio.pl'],
    META_MERGE       => {
        'meta-spec' => { version => 2 },
        resources   => {
            repository => {
                type => 'git',
                url  => 'https://github.com/rjpcasalino/am_radio.git',
                web  => 'https://github.com/rjpcasalino/am_radio',
            },
        },
    },
);
