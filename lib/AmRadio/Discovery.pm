package AmRadio::Discovery;

# ==============================================================================
# AmRadio::Discovery - station search and stream metadata
#
# Handles:
#   * uri_escape()                  - UTF-8-correct percent encoder
#   * run_capture()                 - safe shell-free subprocess capture
#   * require_tool()                - check for an external binary
#   * api_search()                  - shared Radio-Browser.info query helper
#   * discover_stations()           - quick name search (-f QUERY)
#   * discover_stations_interactive() - interactive multi-criteria search (-f)
#   * dump_info()                   - stream metadata via ffprobe
# ==============================================================================

use strict;
use warnings;
use Exporter 'import';
use POSIX ();
use JSON::PP qw(decode_json);
use Encode   qw(encode_utf8);
use AmRadio::Colors qw(:all);
use AmRadio::Config qw(save_station $CONFIG_FILE);

our @EXPORT_OK = qw(
    uri_escape
    run_capture
    require_tool
    discover_stations
    discover_stations_interactive
    dump_info
);

# Base URL shared by all Radio-Browser.info queries
my $RB_BASE = 'https://de1.api.radio-browser.info/json/stations/search';

# ------------------------------------------------------------------------------
# uri_escape - UTF-8-correct percent encoder for URL query strings
# ------------------------------------------------------------------------------
sub uri_escape {
    my ($str) = @_;
    my $bytes = encode_utf8($str);
    $bytes =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/ge;
    return $bytes;
}

# ------------------------------------------------------------------------------
# run_capture - safe replacement for backticks; no shell involved
# ------------------------------------------------------------------------------
sub run_capture {
    my (@cmd) = @_;
    my $pid = open(my $ph, '-|');
    return undef unless defined $pid;
    if ($pid == 0) {
        open(STDERR, '>', '/dev/null');
        exec(@cmd) or POSIX::_exit(127);
    }
    local $/;
    my $output = <$ph>;
    close $ph;
    return $output;
}

# ------------------------------------------------------------------------------
# require_tool - die with a friendly message if $tool isn't on PATH
# ------------------------------------------------------------------------------
sub require_tool {
    my ($tool) = @_;
    if (system("command -v $tool > /dev/null 2>&1") != 0) {
        print STDERR "${YELLOW}Error: '$tool' is required but not installed.${RESET}\n";
        exit 1;
    }
}

# ------------------------------------------------------------------------------
# _has_tool - silent version; returns 1/0
# ------------------------------------------------------------------------------
sub _has_tool {
    my ($tool) = @_;
    return system("command -v $tool > /dev/null 2>&1") == 0 ? 1 : 0;
}

# ------------------------------------------------------------------------------
# api_search - execute a Radio-Browser.info search and return an arrayref.
# $params is a hashref of query-string key/value pairs (already validated by
# the caller). Returns undef on network/parse error.
# ------------------------------------------------------------------------------
sub api_search {
    my ($params, $limit) = @_;
    $limit //= 25;

    my @parts;
    for my $k (sort keys %$params) {
        push @parts, uri_escape($k) . '=' . uri_escape($params->{$k});
    }
    push @parts, "limit=$limit", 'hidebroken=true', 'order=votes', 'reverse=true';

    my $url = $RB_BASE . '?' . join('&', @parts);
    my $response = run_capture('curl', '-sL', '--max-time', '10', $url);
    my $data = eval { decode_json($response // '') };
    return undef if $@ || ref($data) ne 'ARRAY';
    return $data;
}

# ------------------------------------------------------------------------------
# _display_results - print a numbered list of station search results.
# Returns the count of results displayed.
# ------------------------------------------------------------------------------
sub _display_results {
    my ($data, $verbose) = @_;
    my $count = scalar @$data;
    return 0 unless $count;

    print "${GREEN}Found $count station(s):${RESET}\n\n";
    for my $i (0 .. $count - 1) {
        my $s        = $data->[$i];
        my $name     = $s->{name}     // '(unknown)';
        my $bitrate  = $s->{bitrate}  // 0;
        my $country  = $s->{country}  // '';
        my $tags     = $s->{tags}     // '';

        if ($verbose) {
            my $state    = $s->{state}    // '';
            my $language = $s->{language} // '';
            my $votes    = $s->{votes}    // 0;

            printf "  %s%2d)%s %s%s%s\n", $CYAN, $i+1, $RESET, $BOLD, $name, $RESET;
            my @loc;
            push @loc, $state   if length $state;
            push @loc, $country if length $country;
            printf "      ${DIM}Location:${RESET} %s\n", join(', ', @loc) if @loc;
            printf "      ${DIM}Quality:${RESET} %s kbps", $bitrate;
            printf " ${DIM}|${RESET} ${DIM}Votes:${RESET} %s", $votes if $votes > 0;
            print "\n";
            printf "      ${DIM}Language:${RESET} $language\n" if length $language;
            if (length $tags) {
                my $t = length($tags) > 60 ? substr($tags, 0, 57) . '...' : $tags;
                print "      ${YELLOW}Tags:${RESET} $t\n";
            }
            print "\n" if $i < $count - 1;
        } else {
            printf "  %s%d)%s %s%s%s (%s kbps)", $CYAN, $i+1, $RESET, $BOLD, $name, $RESET, $bitrate;
            print " ${DIM}- $country${RESET}" if length $country;
            print "\n";
            if (length $tags) {
                my $t = length($tags) > 60 ? substr($tags, 0, 57) . '...' : $tags;
                print "     ${YELLOW}Tags:${RESET} $t\n";
            }
        }
    }
    return $count;
}

# ------------------------------------------------------------------------------
# _prompt_save - offer to save one of the results to the config file.
# ------------------------------------------------------------------------------
sub _prompt_save {
    my ($data, $count, $prompt) = @_;
    $prompt //= "\nEnter a number to SAVE to your list (or press Enter to exit): ";
    print "${BOLD}$prompt${RESET}";
    my $choice = <STDIN>;
    chomp $choice if defined $choice;
    if (defined $choice && $choice =~ /^\d+$/ && $choice >= 1 && $choice <= $count) {
        my $picked = $data->[$choice - 1];
        my $name   = $picked->{name} // 'Unknown Station';
        my $url    = $picked->{url}  // '';
        save_station($name, $url);
        print "${GREEN}[\x{2713}] Saved '$name' to $CONFIG_FILE!${RESET}\n";
    }
}

# ------------------------------------------------------------------------------
# discover_stations - quick name search triggered by -f QUERY
# ------------------------------------------------------------------------------
sub discover_stations {
    my ($query) = @_;
    require_tool('curl');

    # No query: fall through to the interactive menu
    unless (defined $query && length $query) {
        discover_stations_interactive();
        return;
    }

    print "\n${BOLD}${CYAN}>> Searching Radio-Browser.info for: '$query'...${RESET}\n\n";
    my $data = api_search({ name => $query }, 15);
    unless (defined $data) {
        print STDERR "${YELLOW}Error: Could not parse response from Radio-Browser.info.${RESET}\n";
        exit 1;
    }
    unless (@$data) {
        print "No active stations found for that query.\n";
        exit 0;
    }
    my $count = _display_results($data, 0);
    _prompt_save($data, $count);
    exit 0;
}

# ------------------------------------------------------------------------------
# discover_stations_interactive - menu-driven multi-criteria search
# ------------------------------------------------------------------------------
sub discover_stations_interactive {
    require_tool('curl');

    print "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${RESET}\n";
    print "${BOLD}${CYAN}║      Radio Station Discovery - Radio-Browser.info        ║${RESET}\n";
    print "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${RESET}\n\n";
    print "Search options:\n";
    print "  ${CYAN}1)${RESET} By station name or keyword\n";
    print "  ${CYAN}2)${RESET} By country\n";
    print "  ${CYAN}3)${RESET} By country + state/region\n";
    print "  ${CYAN}4)${RESET} By tag/genre\n";
    print "  ${CYAN}5)${RESET} By language\n";
    print "  ${CYAN}6)${RESET} Advanced multi-criteria search\n\n";
    print "Select search type [1-6]: ";

    my $type = <STDIN>;
    chomp $type if defined $type;

    my %params;
    my $search_desc;

    if ($type eq '1') {
        print "Enter station name or keyword: ";
        my $q = <STDIN>; chomp $q if defined $q; return unless length $q;
        %params = (name => $q);
        $search_desc = "stations matching '$q'";

    } elsif ($type eq '2') {
        print "Enter country name or code: ";
        my $c = <STDIN>; chomp $c if defined $c; return unless length $c;
        %params = (country => $c);
        $search_desc = "stations in $c";

    } elsif ($type eq '3') {
        print "Enter country: ";
        my $c = <STDIN>; chomp $c if defined $c; return unless length $c;
        print "Enter state/region: ";
        my $s = <STDIN>; chomp $s if defined $s; return unless length $s;
        %params = (country => $c, state => $s);
        $search_desc = "stations in $s, $c";

    } elsif ($type eq '4') {
        print "Enter tag/genre: ";
        my $t = <STDIN>; chomp $t if defined $t; return unless length $t;
        %params = (tag => $t);
        $search_desc = "stations tagged with '$t'";

    } elsif ($type eq '5') {
        print "Enter language: ";
        my $l = <STDIN>; chomp $l if defined $l; return unless length $l;
        %params = (language => $l);
        $search_desc = "stations broadcasting in $l";

    } elsif ($type eq '6') {
        print "\n${BOLD}Advanced Search - leave blank to skip any field${RESET}\n";
        for my $f (
            [name     => 'Station name/keyword'],
            [country  => 'Country'],
            [state    => 'State/Region'],
            [tag      => 'Tag/Genre'],
            [language => 'Language'],
        ) {
            my ($key, $label) = @$f;
            print "$label: ";
            my $v = <STDIN>; chomp $v if defined $v;
            $params{$key} = $v if defined $v && length $v;
        }
        unless (%params) {
            print "${YELLOW}No search criteria provided.${RESET}\n";
            return;
        }
        $search_desc = "stations matching your criteria";

    } else {
        print "${YELLOW}Invalid selection.${RESET}\n";
        return;
    }

    print "\n${BOLD}${CYAN}>> Searching for $search_desc...${RESET}\n\n";
    my $data = api_search(\%params, 25);
    unless (defined $data) {
        print STDERR "${YELLOW}Error: Could not parse response from Radio-Browser.info.${RESET}\n";
        print STDERR "${DIM}(Network issue or API temporarily unavailable)${RESET}\n";
        exit 1;
    }
    unless (@$data) {
        print "No active stations found for that query.\n";
        print "${DIM}Try broadening your search criteria or different keywords.${RESET}\n";
        exit 0;
    }
    my $count = _display_results($data, 1);
    _prompt_save($data, $count);
    exit 0;
}

# ------------------------------------------------------------------------------
# dump_info - peek at a stream's metadata via ffprobe
# ------------------------------------------------------------------------------
sub dump_info {
    my ($url) = @_;
    print "\n${BOLD}${CYAN}=== Stream Information ===${RESET}\n";

    unless (_has_tool('ffprobe')) {
        print "  ${YELLOW}(Install 'ffprobe' to see deep metadata)${RESET}\n";
        print "${BOLD}${CYAN}==========================${RESET}\n\n";
        return;
    }

    my $probe = run_capture(
        'ffprobe',
        '-v', 'quiet',
        '-timeout', '5000000',
        '-show_entries', 'format_tags',
        '-of', 'default=noprint_wrappers=1:nokey=0',
        $url,
    );

    if (!defined $probe || $probe eq '') {
        print "  ${YELLOW}No metadata headers found. The station might not broadcast tags.${RESET}\n";
        print "${BOLD}${CYAN}==========================${RESET}\n\n";
        return;
    }

    my %seen;
    for my $line (split /\n/, $probe) {
        next unless $line =~ /=(.*)$/;
        my $value = $1;
        next if $value =~ /^\s*$/;

        my $out;
        if    ($line =~ /icy-name=/         || $line =~ /service_name=/) { $out = "  Station: $value" }
        elsif ($line =~ /icy-genre=/        || $line =~ /\bgenre=/     ) { $out = "  Genre:   $value" }
        elsif ($line =~ /icy-br=/           || $line =~ /\bbitrate=/   ) { $out = "  Bitrate: $value kbps" }
        elsif ($line =~ /icy-description=/                             ) { $out = "  Desc:    $value" }
        elsif ($line =~ /StreamTitle=/      || $line =~ /\btitle=/     ) { $out = "  Track:   $value" }
        else  { next }

        print "$out\n" unless $seen{$out}++;
    }

    print "${BOLD}${CYAN}==========================${RESET}\n\n";
}

1;
