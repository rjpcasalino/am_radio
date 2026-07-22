#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile tempdir);
use lib '../lib';

# We need to override $CONFIG_FILE before use_ok loads the module,
# so we set it immediately after importing.
use_ok('AmRadio::Config', qw(load_stations list_stations save_station
                              $CONFIG_FILE @STATIONS));

# Write a temporary config file
my $tmpdir = tempdir(CLEANUP => 1);
my $tmpfile = "$tmpdir/test_stations";

open(my $fh, '>', $tmpfile) or die "Cannot write: $!";
print $fh "# comment\n";
print $fh "\n";                               # blank line
print $fh "Test FM::http://example.com/1\n";
print $fh "Test AM::http://example.com/2\n";
close $fh;

{ no warnings 'once'; $AmRadio::Config::CONFIG_FILE = $tmpfile; }
load_stations();

is(scalar @AmRadio::Config::STATIONS, 2, 'load_stations: reads 2 non-comment entries');
like($AmRadio::Config::STATIONS[0], qr/^Test FM::/, 'load_stations: first entry correct');
like($AmRadio::Config::STATIONS[1], qr/^Test AM::/, 'load_stations: second entry correct');

# save_station appends and updates @STATIONS
save_station('New Wave', 'http://example.com/3');
is(scalar @AmRadio::Config::STATIONS, 3, 'save_station: appended to in-memory list');
like($AmRadio::Config::STATIONS[2], qr/^New Wave::/, 'save_station: new entry format');

# Verify persistence
open(my $in, '<', $tmpfile) or die;
my @lines = grep { /^[^#\s]/ } <$in>;
close $in;
is(scalar @lines, 3, 'save_station: persisted to config file');

done_testing();
