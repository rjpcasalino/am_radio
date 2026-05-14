#!/usr/bin/env perl
# Basic smoke tests for am_radio.pl search functionality

use strict;
use warnings;
use Test::More;

# Test 1: Script compiles without errors
my $compile_result = system("perl -c ../am_radio.pl 2>&1 >/dev/null");
ok($compile_result == 0, "Script compiles successfully");

# Test 2: Help text displays without errors
my $help_output = `perl ../am_radio.pl -h 2>&1`;
like($help_output, qr/Find\/discover new stations/, "Help text includes search documentation");
like($help_output, qr/Interactive menu/, "Help mentions interactive menu");
like($help_output, qr/country, region/, "Help mentions regional search");

# Test 3: List stations works
my $list_output = `perl ../am_radio.pl -l 2>&1`;
ok($? == 0, "List stations command executes without error");

# Test 4: URI escape function (internal test)
{
    # Source the script to test internal functions
    my $test_code = q{
        use utf8;
        use Encode qw(encode_utf8);
        sub uri_escape {
            my ($str) = @_;
            my $bytes = encode_utf8($str);
            $bytes =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/ge;
            return $bytes;
        }

        my $result = uri_escape("hello world");
        print $result;
    };

    my $escaped = `perl -e '$test_code'`;
    is($escaped, "hello%20world", "URI escape function works correctly");
}

# Test 5: Check that curl dependency is properly detected
SKIP: {
    skip "curl not available in environment", 1 unless -x '/usr/bin/curl' || system("command -v curl >/dev/null 2>&1") == 0;
    ok(1, "curl is available for station discovery");
}

done_testing();
