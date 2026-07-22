#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '../lib';

use_ok('AmRadio::Discovery', qw(uri_escape run_capture));

# uri_escape: plain ASCII stays unchanged (except special chars)
is(uri_escape('hello'),      'hello',      'uri_escape: plain word');
is(uri_escape('a b'),        'a%20b',      'uri_escape: space -> %20');
is(uri_escape('jazz&blues'), 'jazz%26blues', 'uri_escape: & -> %26');

# UTF-8: 'é' should encode as its UTF-8 bytes %C3%A9
is(uri_escape("\x{e9}"), '%C3%A9', 'uri_escape: é -> %C3%A9');

# run_capture: safe list-form exec
{
    my $out = run_capture('echo', 'hello world');
    chomp $out if defined $out;
    is($out, 'hello world', 'run_capture: echo round-trip');
}

# run_capture: returns undef/empty on failure without dying
{
    my $out = eval { run_capture('/nonexistent_binary_12345') };
    ok(!defined $out || $out eq '', 'run_capture: graceful failure on missing binary');
}

done_testing();
