#!/usr/bin/env perl
# Tests for Radio-Browser.info API integration and TUI search functionality

use strict;
use warnings;
use Test::More;
use JSON::PP;

# Skip all tests if curl is not available
unless (system('which curl >/dev/null 2>&1') == 0) {
    plan skip_all => 'curl not available for API testing';
}

# Skip all tests if network is unavailable
my $network_check = `curl -sL --max-time 5 https://de1.api.radio-browser.info/json/stats 2>&1`;
unless ($? == 0) {
    plan skip_all => 'Radio-Browser.info API not accessible (network issue or blocked)';
}

plan tests => 13;

# Test 1: API responds to basic name search
my $response = `curl -sL --max-time 8 'https://de1.api.radio-browser.info/json/stations/search?name=jazz&limit=5&hidebroken=true&order=votes&reverse=true' 2>&1`;
ok($? == 0, 'API call executes successfully');

# Test 2: Response is valid JSON
my $data = eval { decode_json($response) };
ok(!$@, 'API returns valid JSON') or diag("JSON parse error: $@");

# Test 3: Response is an array
ok(ref($data) eq 'ARRAY', 'API returns an array of stations');

# Test 4: Check response structure
if (@$data) {
    my $first = $data->[0];
    ok(exists $first->{name}, 'Station has name field');
    ok(exists $first->{url}, 'Station has url field');
    ok(exists $first->{bitrate}, 'Station has bitrate field');
    ok(exists $first->{votes}, 'Station has votes field');

    # Test 5: Verify ordering by votes (descending)
    if (@$data >= 2) {
        ok($data->[0]{votes} >= $data->[1]{votes},
           'Results ordered by votes (descending)');
    } else {
        pass('Only one result, skipping vote ordering test');
    }
} else {
    # Skip structure tests if no results
    skip('No results returned', 5);
}

# Test 6: Test with larger limit to see actual API capabilities
my $large_response = `curl -sL --max-time 10 'https://de1.api.radio-browser.info/json/stations/search?name=radio&limit=50&hidebroken=true&order=votes&reverse=true' 2>&1`;
my $large_data = eval { decode_json($large_response) };
ok(ref($large_data) eq 'ARRAY', 'API handles larger limit requests');
my $large_count = scalar(@$large_data);
ok($large_count > 0, "Large search returns results (got $large_count)");
diag("Large search with limit=50 returned $large_count stations");

# Test 7: Test with limit=100 (maximum useful for pagination)
my $max_response = `curl -sL --max-time 10 'https://de1.api.radio-browser.info/json/stations/search?name=music&limit=100&hidebroken=true&order=votes&reverse=true' 2>&1`;
my $max_data = eval { decode_json($max_response) };
ok(ref($max_data) eq 'ARRAY', 'API handles maximum limit requests');
my $max_count = scalar(@$max_data);
diag("Maximum search with limit=100 returned $max_count stations");

# Test 8: Test empty/no results case
my $empty_response = `curl -sL --max-time 8 'https://de1.api.radio-browser.info/json/stations/search?name=xyzqwertyrandomnonexistentstation12345&limit=5&hidebroken=true&order=votes&reverse=true' 2>&1`;
my $empty_data = eval { decode_json($empty_response) };
ok(ref($empty_data) eq 'ARRAY' && @$empty_data == 0,
   'API returns empty array for no matches');

# Test 9: Verify our URI escaping function works (from main script)
sub uri_escape {
    my ($str) = @_;
    require Encode;
    my $bytes = Encode::encode_utf8($str);
    $bytes =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/ge;
    return $bytes;
}

my $escaped = uri_escape("rock & roll");
is($escaped, "rock%20%26%20roll", 'URI escape handles spaces and special chars');

done_testing();
