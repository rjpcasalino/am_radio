#!/usr/bin/env perl
# Basic sanity tests for am_radio.pl

use strict;
use warnings;
use Test::More tests => 6;

# Test 1: Script exists and is readable
ok(-f '../am_radio.pl', 'am_radio.pl exists');
ok(-r '../am_radio.pl', 'am_radio.pl is readable');

# Test 2: Script compiles without errors
my $compile_check = `perl -c ../am_radio.pl 2>&1`;
like($compile_check, qr/syntax OK/, 'Script compiles without syntax errors');

# Test 3: Help output works
my $help_output = `perl ../am_radio.pl -h 2>&1`;
like($help_output, qr/Usage:/, 'Help flag produces usage output');
like($help_output, qr/-v/, 'Help mentions verbose flag');

# Test 4: Verbose flag is recognized (should exit with help or continue)
my $verbose_help = `perl ../am_radio.pl -h -v 2>&1`;
ok($? >> 8 == 0, 'Verbose flag is recognized without error');

done_testing();
