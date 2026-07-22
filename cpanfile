# cpanfile — dependency manifest for am_radio
#
# All listed modules ship with Perl 5.14+ core, so no CPAN installs are
# required on a standard Perl installation.  The file is provided so that
# `cpanm --installdeps .` works out of the box on any machine where a module
# might be missing (e.g. a stripped-down Docker image).

requires 'perl',             '5.014';
requires 'strict';
requires 'warnings';
requires 'utf8';
requires 'File::Basename';
requires 'Getopt::Long',     '2.33';   # bundling + no_ignore_case config
requires 'JSON::PP',         '2.27';   # core since 5.14
requires 'IO::Socket::UNIX';
requires 'IO::Select';
requires 'POSIX';
requires 'Time::HiRes';
requires 'Encode';
requires 'Exporter';

on 'test' => sub {
    requires 'Test::More',   '0.96';
};
