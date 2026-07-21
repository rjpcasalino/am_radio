#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use lib '../lib';

# Require the module without running any I/O side-effects
use_ok('AmRadio::Colors');

# Verify each constant is defined and is a non-empty string
AmRadio::Colors->import(':all');

my @names = qw( $CYAN $GREEN $YELLOW $RED $MAGENTA $WHITE $BOLD $DIM $RESET );
for my $name (@names) {
    no strict 'refs';
    my $bare = $name;
    $bare =~ s/^\$//;
    my $val = ${"AmRadio::Colors::$bare"};
    ok(defined $val && length $val, "AmRadio::Colors: $name is defined and non-empty");
}

done_testing();
