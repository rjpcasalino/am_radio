#!/usr/bin/env perl

# ==============================================================================
# am_radio.pl - A command-line internet radio player (with optional TUI mode)
# ------------------------------------------------------------------------------
# Perl rewrite of the original am_radio.zsh script.
#
# What this script does:
#   * Plays internet radio streams via the external 'mpv' player
#   * Maintains a list of saved stations in ~/.radio_stations
#   * Discovers new stations via the public Radio-Browser.info API
#   * Optionally applies a lo-fi "old time AM radio" audio filter
#   * Optionally dumps stream metadata (ICY/ID3 tags) using 'ffprobe'
#   * Optionally drives a vintage-tube-radio TUI (-t) with AM_RADIO branding,
#     frequency dial, presets, live track display and in-TUI station search
#
# External programs required at runtime:
#   * mpv      - to actually play the audio (mandatory)
#   * curl     - only needed for the -f (find) feature
#   * ffprobe  - only needed for the -i (info) feature
# ==============================================================================

use strict;            # Force variable declarations - catches typos at compile time
use warnings;          # Enable runtime warnings about suspicious constructs
use utf8;              # Source file is UTF-8; lets length()/substr() count chars not bytes
use Getopt::Std;       # Core module for parsing single-letter command line options
use File::Basename;    # Provides basename() so we can show a clean script name
use JSON::PP;          # Pure-Perl JSON parser (core since 5.14) - replaces the 'jq' tool
use IO::Socket::UNIX;  # Unix-domain socket - for talking to mpv's IPC server
use IO::Select;        # Multiplex I/O - lets us add a timeout to IPC reads
use POSIX qw(:termios_h :sys_wait_h);  # termios for raw terminal mode, WNOHANG for non-blocking waitpid
use Time::HiRes qw(time sleep);        # Sub-second time() and sleep() for the TUI event loop
use Encode qw(encode_utf8);            # UTF-8-correct URL escaping in uri_escape()

# Make sure box-drawing chars and other non-ASCII output gets encoded properly
# on the way to the terminal. Without this, characters like ╔ get mangled.
binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# ==============================================================================
# CONFIGURATION & SETUP
# ==============================================================================

my $CONFIG_FILE = "$ENV{HOME}/.radio_stations";
my @STATIONS;

# Verbose logging flag - set via -v command-line option
my $VERBOSE = 0;

# ANSI color escape sequences. Note: \e is the literal ESC byte (0x1B).
my $CYAN    = "\e[36m";
my $GREEN   = "\e[32m";
my $YELLOW  = "\e[33m";
my $RED     = "\e[31m";
my $MAGENTA = "\e[35m";
my $WHITE   = "\e[37m";
my $BOLD    = "\e[1m";
my $DIM     = "\e[2m";
my $RESET   = "\e[0m";

# ------------------------------------------------------------------------------
# verbose_log - print timestamped debug messages when -v is enabled
# ------------------------------------------------------------------------------
sub verbose_log {
    return unless $VERBOSE;
    my ($msg) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
    my $timestamp = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                           $year + 1900, $mon + 1, $mday, $hour, $min, $sec);
    print STDERR "${DIM}[$timestamp] [am_radio] $msg${RESET}\n";
}

# ------------------------------------------------------------------------------
# First-run bootstrap (unchanged from original)
# ------------------------------------------------------------------------------
if (! -f $CONFIG_FILE) {
    print "${YELLOW}Creating default station list at $CONFIG_FILE...${RESET}\n";
    open(my $fh, '>', $CONFIG_FILE) or die "Cannot create $CONFIG_FILE: $!";
    print $fh <<'END';
# Internet Radio Stations Config
# Format: Station Name::Stream URL

NPR News (US)::https://npr-ice.streamguys1.com/live.mp3
KEXP Seattle (music + talk)::https://kexp-mp3-128.streamguys1.com/kexp128.mp3
WFMU Freeform Radio (NJ)::https://stream0.wfmu.org/freeform-high.aac
WWOZ New Orleans (community)::https://wwoz-sc.streamguys1.com/wwoz-hi.mp3
KUSC Classical (Los Angeles)::http://128.mp3.kusc.live/
END
    close($fh);
}

# ------------------------------------------------------------------------------
# Read the config file
# ------------------------------------------------------------------------------
open(my $cfg, '<', $CONFIG_FILE) or die "Cannot open $CONFIG_FILE: $!";
while (my $line = <$cfg>) {
    chomp $line;
    next if $line =~ /^\s*$/;
    next if $line =~ /^\s*#/;
    push @STATIONS, $line;
}
close($cfg);

# ==============================================================================
# CLI FUNCTIONS (non-TUI)
# ==============================================================================

sub show_help {
    my $name = basename($0);
    print <<"END";
${BOLD}Usage:${RESET} $name [OPTIONS] [STATION_NUMBER]

Play and discover internet radio streams directly from the command line.

${BOLD}Options:${RESET}
  -s NUM     Select station by number (e.g., -s 2)
  -l         List all saved stations
  -f [QUERY] Find/discover new stations on Radio-Browser.info
             * With QUERY: quick name search (e.g., -f 'jazz', -f 'BBC')
             * Without QUERY: interactive menu to search by country, region,
               language, tag/genre, or advanced multi-criteria search
  -o         Enable 'Old Time Radio' audio filter (lo-fi AM sound)
  -i         Dump initial station metadata (ffprobe required)
  -t         Tuner mode: vintage TUI with dial and presets
  -v         Verbose logging (debug mpv lifecycle, IPC, audio drops)
  -h         Show this help message and exit

${BOLD}Special station presets:${RESET}
  --afn      Load American Forces Network (AFN) stations
             Includes AFN GO (Tokyo, Humphreys, Bahrain), AFN 360 stations
             from Guantanamo Bay, Bahrain, Benelux, Bavaria, Vicenza,
             Wiesbaden, and AFN İncirlik (Turkey)

${BOLD}Discovery examples:${RESET}
  $name -f                     # Interactive menu (by country, region, tag, etc.)
  $name -f 'jazz'              # Quick search for stations with 'jazz' in name
  $name -f 'BBC'               # Quick search for 'BBC' stations

${BOLD}AFN examples:${RESET}
  $name --afn -l               # List all AFN stations
  $name --afn -t               # Launch TUI with AFN stations
  $name --afn -s 1             # Play AFN 360 (first station)

${BOLD}Tuner mode keys:${RESET}
  ${CYAN}<-${RESET} ${CYAN}->${RESET}        Tune to previous / next station
  ${CYAN}1${RESET}-${CYAN}9${RESET}          Jump to preset (first 9 stations)
  ${CYAN}o${RESET}            Toggle Lo-Fi AM filter
  ${CYAN}i${RESET}            Show verbose stream info (press any key to return)
  ${CYAN}r${RESET}            Re-tune (kick mpv if a stream stalls)
  ${CYAN}f${RESET}            Search for stations (music keeps playing)
  ${CYAN}q${RESET} / ${CYAN}Esc${RESET}      Quit
END
    exit 0;
}

sub list_stations {
    for my $i (0 .. $#STATIONS) {
        my ($name) = split /::/, $STATIONS[$i], 2;
        printf "  %s%d)%s %s\n", $CYAN, $i + 1, $RESET, $name;
    }
}

# ------------------------------------------------------------------------------
# uri_escape - UTF-8-correct percent-encoder for URL query strings.
# Runs the input through encode_utf8 first so multibyte chars like 'é' get
# encoded as their UTF-8 bytes (%C3%A9) rather than as their codepoint (%E9).
# ------------------------------------------------------------------------------
sub uri_escape {
    my ($str) = @_;
    my $bytes = encode_utf8($str);              # multibyte chars -> UTF-8 bytes
    $bytes =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/ge;
    return $bytes;
}

# ------------------------------------------------------------------------------
# run_capture - safe replacement for backticks. Takes a command and arguments
# as a list, runs it without involving a shell, and returns its stdout. This
# means a stream URL containing shell metacharacters can't trigger code
# execution the way it would with `cmd "$var"`.
# ------------------------------------------------------------------------------
sub run_capture {
    my (@cmd) = @_;
    my $pid = open(my $ph, '-|');               # list-form pipe open: no shell involved
    return undef unless defined $pid;

    if ($pid == 0) {
        # Child: silence stderr, then exec the requested command.
        open(STDERR, '>', '/dev/null');
        exec(@cmd) or POSIX::_exit(127);
    }

    # Parent: slurp the child's stdout.
    local $/;                                    # Slurp mode (read whole stream as one string)
    my $output = <$ph>;
    close $ph;
    return $output;
}

# ------------------------------------------------------------------------------
# discover_stations_interactive - presents a menu-driven interface for
# discovering radio stations by various search criteria:
#   1) Simple name/keyword search (original behavior)
#   2) Search by country (e.g., "USA", "Germany", "Brazil")
#   3) Search by country + state/region (e.g., "USA" then "California")
#   4) Search by tag (e.g., "jazz", "classical", "news")
#   5) Search by language (e.g., "english", "spanish", "french")
#
# This makes Radio-Browser.info exploration much deeper, allowing users to
# discover stations by geography and genre rather than just station name.
# ------------------------------------------------------------------------------
sub discover_stations_interactive {
    if (system("command -v curl > /dev/null 2>&1") != 0) {
        print STDERR "${YELLOW}Error: Stream discovery requires 'curl' to be installed.${RESET}\n";
        exit 1;
    }

    print "\n${BOLD}${CYAN}╔═══════════════════════════════════════════════════════════╗${RESET}\n";
    print "${BOLD}${CYAN}║      Radio Station Discovery - Radio-Browser.info        ║${RESET}\n";
    print "${BOLD}${CYAN}╚═══════════════════════════════════════════════════════════╝${RESET}\n\n";

    print "Search options:\n";
    print "  ${CYAN}1)${RESET} By station name or keyword (e.g., 'jazz', 'BBC', 'rock')\n";
    print "  ${CYAN}2)${RESET} By country (e.g., 'USA', 'Germany', 'Japan')\n";
    print "  ${CYAN}3)${RESET} By country + state/region (e.g., 'USA' + 'California')\n";
    print "  ${CYAN}4)${RESET} By tag/genre (e.g., 'classical', 'news', 'electronic')\n";
    print "  ${CYAN}5)${RESET} By language (e.g., 'english', 'spanish', 'french')\n";
    print "  ${CYAN}6)${RESET} Advanced multi-criteria search\n\n";

    print "Select search type [1-6]: ";
    my $search_type = <STDIN>;
    chomp $search_type if defined $search_type;

    # Build the API URL based on user's choice
    my $api_url;
    my $search_desc;

    if ($search_type eq '1') {
        # Simple name/keyword search (original behavior)
        print "Enter station name or keyword: ";
        my $query = <STDIN>;
        chomp $query if defined $query;
        return unless length $query;

        $search_desc = "stations matching '$query'";
        $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                 . '?name=' . uri_escape($query)
                 . '&limit=25&hidebroken=true&order=votes&reverse=true';

    } elsif ($search_type eq '2') {
        # Search by country
        print "Enter country name or code (e.g., 'USA', 'Germany', 'Brazil'): ";
        my $country = <STDIN>;
        chomp $country if defined $country;
        return unless length $country;

        $search_desc = "stations in $country";
        $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                 . '?country=' . uri_escape($country)
                 . '&limit=25&hidebroken=true&order=votes&reverse=true';

    } elsif ($search_type eq '3') {
        # Search by country + state
        print "Enter country (e.g., 'USA', 'Australia', 'Canada'): ";
        my $country = <STDIN>;
        chomp $country if defined $country;
        return unless length $country;

        print "Enter state/region (e.g., 'California', 'New South Wales', 'Ontario'): ";
        my $state = <STDIN>;
        chomp $state if defined $state;
        return unless length $state;

        $search_desc = "stations in $state, $country";
        $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                 . '?country=' . uri_escape($country)
                 . '&state=' . uri_escape($state)
                 . '&limit=25&hidebroken=true&order=votes&reverse=true';

    } elsif ($search_type eq '4') {
        # Search by tag/genre
        print "Enter tag/genre (e.g., 'jazz', 'classical', 'news', 'rock'): ";
        my $tag = <STDIN>;
        chomp $tag if defined $tag;
        return unless length $tag;

        $search_desc = "stations tagged with '$tag'";
        $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                 . '?tag=' . uri_escape($tag)
                 . '&limit=25&hidebroken=true&order=votes&reverse=true';

    } elsif ($search_type eq '5') {
        # Search by language
        print "Enter language (e.g., 'english', 'spanish', 'french', 'german'): ";
        my $lang = <STDIN>;
        chomp $lang if defined $lang;
        return unless length $lang;

        $search_desc = "stations broadcasting in $lang";
        $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                 . '?language=' . uri_escape($lang)
                 . '&limit=25&hidebroken=true&order=votes&reverse=true';

    } elsif ($search_type eq '6') {
        # Advanced multi-criteria search
        print "\n${BOLD}Advanced Search - leave blank to skip any field${RESET}\n";

        print "Station name/keyword: ";
        my $name = <STDIN>;
        chomp $name if defined $name;

        print "Country: ";
        my $country = <STDIN>;
        chomp $country if defined $country;

        print "State/Region: ";
        my $state = <STDIN>;
        chomp $state if defined $state;

        print "Tag/Genre: ";
        my $tag = <STDIN>;
        chomp $tag if defined $tag;

        print "Language: ";
        my $lang = <STDIN>;
        chomp $lang if defined $lang;

        # Build URL with all provided parameters
        my @params;
        push @params, 'name=' . uri_escape($name) if length $name;
        push @params, 'country=' . uri_escape($country) if length $country;
        push @params, 'state=' . uri_escape($state) if length $state;
        push @params, 'tag=' . uri_escape($tag) if length $tag;
        push @params, 'language=' . uri_escape($lang) if length $lang;

        if (@params == 0) {
            print "${YELLOW}No search criteria provided.${RESET}\n";
            return;
        }

        $search_desc = "stations matching your criteria";
        $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                 . '?' . join('&', @params)
                 . '&limit=25&hidebroken=true&order=votes&reverse=true';

    } else {
        print "${YELLOW}Invalid selection.${RESET}\n";
        return;
    }

    # Execute the search
    print "\n${BOLD}${CYAN}>> Searching for $search_desc...${RESET}\n\n";

    # Pass --max-time so a hung server can't freeze us forever.
    my $response = run_capture('curl', '-sL', '--max-time', '10', $api_url);

    my $data = eval { decode_json($response // '') };
    if ($@ || ref($data) ne 'ARRAY') {
        print STDERR "${YELLOW}Error: Could not parse response from Radio-Browser.info.${RESET}\n";
        print STDERR "${DIM}(Network issue or API temporarily unavailable)${RESET}\n";
        exit 1;
    }

    my $count = scalar @$data;
    if ($count == 0) {
        print "No active stations found for that query.\n";
        print "${DIM}Try broadening your search criteria or different keywords.${RESET}\n";
        exit 0;
    }

    # Display results with enhanced metadata
    print "${GREEN}Found $count station(s):${RESET}\n\n";
    for my $i (0 .. $count - 1) {
        my $s = $data->[$i];
        my $name     = $s->{name}    // '(unknown)';
        my $bitrate  = $s->{bitrate} // 0;
        my $country  = $s->{country} // '';
        my $state    = $s->{state}   // '';
        my $tags     = $s->{tags}    // '';
        my $language = $s->{language} // '';
        my $votes    = $s->{votes}   // 0;

        # Format the station entry
        printf "  %s%2d)%s %s%s%s\n",
            $CYAN, $i + 1, $RESET, $BOLD, $name, $RESET;

        # Display location info if available
        my @location;
        push @location, $state if length $state;
        push @location, $country if length $country;
        if (@location) {
            printf "      ${DIM}Location:${RESET} %s\n", join(', ', @location);
        }

        # Display bitrate and vote count
        printf "      ${DIM}Quality:${RESET} %s kbps", $bitrate;
        printf " ${DIM}|${RESET} ${DIM}Votes:${RESET} %s", $votes if $votes > 0;
        print "\n";

        # Display language if available
        if (length $language) {
            print "      ${DIM}Language:${RESET} $language\n";
        }

        # Display tags if available
        if (length $tags) {
            my $tags_truncated = length($tags) > 60 ? substr($tags, 0, 57) . '...' : $tags;
            print "      ${YELLOW}Tags:${RESET} $tags_truncated\n";
        }

        print "\n" if $i < $count - 1;  # Blank line between entries
    }

    # Prompt user to save a station
    print "\n${BOLD}Enter a number to SAVE to your list (or press Enter to exit): ${RESET}";
    my $choice = <STDIN>;
    chomp $choice if defined $choice;

    if (defined $choice && $choice =~ /^\d+$/ && $choice >= 1 && $choice <= $count) {
        my $picked = $data->[$choice - 1];
        my $name = $picked->{name} // 'Unknown Station';
        my $url  = $picked->{url}  // '';

        # Append to the config file
        open(my $out, '>>', $CONFIG_FILE) or die "Cannot append to $CONFIG_FILE: $!";
        print $out $name . '::' . $url . "\n";
        close($out);

        print "${GREEN}[✓] Saved '$name' to $CONFIG_FILE!${RESET}\n";
    }
    exit 0;
}

# ------------------------------------------------------------------------------
# discover_stations - wrapper for backward compatibility with -f flag.
# If a query is provided via -f, it goes directly to a simple name search.
# If no query is provided, launches the interactive menu.
# ------------------------------------------------------------------------------
sub discover_stations {
    my ($query) = @_;

    if (system("command -v curl > /dev/null 2>&1") != 0) {
        print STDERR "${YELLOW}Error: Stream discovery requires 'curl' to be installed.${RESET}\n";
        exit 1;
    }

    # If a query was provided with -f, do a quick name search (original behavior)
    if (defined $query && length $query) {
        print "\n${BOLD}${CYAN}>> Searching Radio-Browser.info for: '$query'...${RESET}\n\n";

        my $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                    . '?name=' . uri_escape($query)
                    . '&limit=15&hidebroken=true&order=votes&reverse=true';

        # Pass --max-time so a hung server can't freeze us forever.
        my $response = run_capture('curl', '-sL', '--max-time', '10', $api_url);

        my $data = eval { decode_json($response // '') };
        if ($@ || ref($data) ne 'ARRAY') {
            print STDERR "${YELLOW}Error: Could not parse response from Radio-Browser.info.${RESET}\n";
            exit 1;
        }

        my $count = scalar @$data;
        if ($count == 0) {
            print "No active stations found for that query.\n";
            exit 0;
        }

        # Display results with enhanced info
        for my $i (0 .. $count - 1) {
            my $s = $data->[$i];
            my $name     = $s->{name}    // '(unknown)';
            my $bitrate  = $s->{bitrate} // 0;
            my $country  = $s->{country} // '';
            my $tags     = $s->{tags}    // '';

            printf "  %s%d)%s %s%s%s (%s kbps)",
                $CYAN, $i + 1, $RESET, $BOLD, $name, $RESET, $bitrate;
            print " ${DIM}- $country${RESET}" if length $country;
            print "\n";

            if (length $tags) {
                my $tags_short = length($tags) > 60 ? substr($tags, 0, 57) . '...' : $tags;
                print "     ${YELLOW}Tags:${RESET} $tags_short\n";
            }
        }

        print "\nEnter a number to SAVE to your list (or press Enter to exit): ";
        my $choice = <STDIN>;
        chomp $choice if defined $choice;

        if (defined $choice && $choice =~ /^\d+$/ && $choice >= 1 && $choice <= $count) {
            my $picked = $data->[$choice - 1];
            my $name = $picked->{name} // 'Unknown Station';
            my $url  = $picked->{url}  // '';

            open(my $out, '>>', $CONFIG_FILE) or die "Cannot append to $CONFIG_FILE: $!";
            print $out $name . '::' . $url . "\n";
            close($out);

            print "${GREEN}[OK] Saved '$name' to $CONFIG_FILE!${RESET}\n";
        }
        exit 0;
    }

    # No query provided - launch interactive menu
    discover_stations_interactive();
}

# ------------------------------------------------------------------------------
# dump_info - peek at a stream's metadata via ffprobe.
# Now uses run_capture() so the URL is passed as a separate argv element and
# can't break out into the shell.
# ------------------------------------------------------------------------------
sub dump_info {
    my ($url) = @_;
    print "\n${BOLD}${CYAN}=== Stream Information ===${RESET}\n";

    if (system("command -v ffprobe > /dev/null 2>&1") != 0) {
        print "  ${YELLOW}(Install 'ffprobe' to see deep metadata)${RESET}\n";
        print "${BOLD}${CYAN}==========================${RESET}\n\n";
        return;
    }

    # ffprobe -timeout is in microseconds (5_000_000us = 5s)
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
        if    ($line =~ /icy-name=/         || $line =~ /service_name=/) { $out = "  Station: $value"; }
        elsif ($line =~ /icy-genre=/        || $line =~ /\bgenre=/     ) { $out = "  Genre:   $value"; }
        elsif ($line =~ /icy-br=/           || $line =~ /\bbitrate=/   ) { $out = "  Bitrate: $value kbps"; }
        elsif ($line =~ /icy-description=/                             ) { $out = "  Desc:    $value"; }
        elsif ($line =~ /StreamTitle=/      || $line =~ /\btitle=/     ) { $out = "  Track:   $value"; }
        else  { next; }

        unless ($seen{$out}++) {
            print "$out\n";
        }
    }

    print "${BOLD}${CYAN}==========================${RESET}\n\n";
}

# ==============================================================================
# IPC: talking to mpv's JSON socket
# ==============================================================================

# ------------------------------------------------------------------------------
# ipc_get_property - send a JSON 'get_property' command and return the value.
# Now bounded by a timeout so a frozen mpv can't hang the caller indefinitely.
# Uses IO::Select to wait at most $timeout seconds across all reads.
# ------------------------------------------------------------------------------
sub ipc_get_property {
    my ($socket_path, $property, $id, $timeout) = @_;
    $timeout //= 0.5;                             # default 500ms ceiling per call

    my $sock = IO::Socket::UNIX->new(
        Type    => SOCK_STREAM,
        Peer    => $socket_path,
        Timeout => 1,
    );
    return undef unless $sock;

    my $request = encode_json({
        command    => [ 'get_property', $property ],
        request_id => $id,
    });
    # syswrite is unbuffered - the IPC server expects each command on one line
    syswrite($sock, "$request\n");

    my $sel = IO::Select->new($sock);
    my $buf = '';
    my $deadline = time() + $timeout;
    my $value;

    while (time() < $deadline) {
        my $remaining = $deadline - time();
        $remaining = 0.05 if $remaining < 0.05;
        my @ready = $sel->can_read($remaining);
        last unless @ready;

        my $chunk;
        my $r = sysread($sock, $chunk, 8192);
        last if !defined $r || $r == 0;
        $buf .= $chunk;

        # mpv's IPC is line-delimited JSON. Pull off one complete line at a
        # time and try to match it against our request_id.
        while ($buf =~ s/^([^\n]*)\n//) {
            my $line = $1;
            next unless length $line;
            my $msg = eval { decode_json($line) };
            next if $@;
            next unless ref($msg) eq 'HASH';

            if (defined $msg->{request_id} && $msg->{request_id} == $id) {
                if (defined $msg->{error} && $msg->{error} eq 'success') {
                    $value = $msg->{data};
                }
                close $sock;
                return $value;                    # found our reply, exit early
            }
            # else: spontaneous event message, ignore
        }
    }

    close $sock;
    return $value;                                # may be undef on timeout
}

# ------------------------------------------------------------------------------
# poll_track_loop - background-mode track watcher (used in non-TUI playback).
# Polls every 5 seconds and prints a "Now Playing" block when the track
# changes. Now actually USES the station/genre/bitrate it fetches (those were
# dead code in the original).
# ------------------------------------------------------------------------------
sub poll_track_loop {
    my ($socket_path) = @_;

    my $waited = 0;
    while (! -S $socket_path) {
        return if $waited >= 15;
        sleep 1;
        $waited++;
    }
    sleep 2;                                      # let mpv connect to stream

    my $last_title;
    my $req_id = 0;

    # Helper: is this metadata value worth showing?
    my $has = sub {
        my ($v) = @_;
        return defined $v && $v =~ /\S/;
    };

    while (1) {
        $req_id++;
        my $title = ipc_get_property($socket_path, 'metadata/icy-title', $req_id);

        if (defined $title && length $title) {
            if (!defined $last_title || $title ne $last_title) {

                $req_id++; my $station = ipc_get_property($socket_path, 'metadata/icy-name',  $req_id);
                $req_id++; my $genre   = ipc_get_property($socket_path, 'metadata/icy-genre', $req_id);
                $req_id++; my $bitrate = ipc_get_property($socket_path, 'metadata/icy-br',    $req_id);

                # Print the full block - this is what the original *intended*
                # to do but never actually wrote out.
                print "\n${BOLD}${CYAN}=== Now Playing ===${RESET}\n";
                print "  Station: $station\n"      if $has->($station);
                print "  Genre:   $genre\n"        if $has->($genre);
                print "  Bitrate: $bitrate kbps\n" if $has->($bitrate);
                print "  Track:   $title\n";
                print "${BOLD}${CYAN}==========================${RESET}\n";

                $last_title = $title;
            }
        }

        sleep 5;                                  # tighter than the original's 30s
    }
}

# ==============================================================================
# TUI MODE - vintage tube-radio terminal UI
# ==============================================================================
#
# Layout (66 cols x 22 rows, Unicode box drawing):
#
#   ╔════════════════════════════════════════════════════════════════╗
#   ║                          AM_RADIO                 [Lo-Fi:OFF] ║
#   ╠════════════════════════════════════════════════════════════════╣
#   ║                                                                ║
#   ║   ┌──────────────────────────────────────────────────────────┐ ║
#   ║   │ ► KEXP Seattle (music + talk)                  920 kHz   │ ║
#   ║   │ ♪  The Beatles — Here Comes the Sun                      │ ║
#   ║   └──────────────────────────────────────────────────────────┘ ║
#   ║                                                                ║
#   ║   FREQUENCY                                                    ║
#   ║                       ▼                                        ║
#   ║   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   ║
#   ║   ╎    ╎    ╎    │    ╎    ╎    ╎    ╎    ╎    ╎    ╎    ╎    ║
#   ║   540   700  900  1080  1260 1440  1620 1700               kHz ║
#   ║                                                                ║
#   ║                         PRESETS  1 2 3 4 5 6 7 8 9            ║
#   ║                                                                ║
#   ║   > Tuning…                                                    ║
#   ╠════════════════════════════════════════════════════════════════╣
#   ║  ◀ ▶ tune   1-9 preset   o lo-fi   r retune   f find   q quit ║
#   ╚════════════════════════════════════════════════════════════════╝
#
# In search mode (press f), the content area (rows 3-17) is replaced with a
# search prompt card and up to 5 Radio-Browser.info results. Music is
# uninterrupted because mpv runs as a separate child process.
#
# The TUI process layout:
#
#       parent perl  --(event loop)--> reads keys, polls IPC, redraws
#            |
#            +--(fork+exec)--> mpv (silent, audio only)
#
# Unlike the non-TUI flow, the parent is the IPC poller here, so no second
# fork is needed. mpv's stdio is redirected to /dev/null so nothing leaks
# onto the screen and disturbs our drawing.
# ==============================================================================

# Visible widths used by the drawing routines. Don't change without re-doing
# the padding maths in the row builders.
my $TUI_WIDTH      = 66;     # total terminal columns we use
my $TUI_INNER      = 64;     # chars between the left and right border
my $TUI_HEIGHT     = 22;     # total rows
my $TUI_DIAL_WIDTH = 56;     # length of the horizontal dial line
my $TUI_DIAL_LEFT  = 4;      # left padding from the inner column 0 of the dial

# ------------------------------------------------------------------------------
# tui_term_setup / tui_term_restore
#
# We use POSIX termios to put STDIN into "raw-ish" mode:
#   * ICANON off : reads return immediately, no waiting for a newline
#   * ECHO   off : keystrokes don't appear on the screen as the user types
#   * VMIN=0,VTIME=0 : sysread returns whatever's available (or nothing)
#
# We deliberately leave ISIG ON, so Ctrl-C still generates SIGINT — our
# signal handler then runs the cleanup routine.
# ------------------------------------------------------------------------------
sub tui_term_setup {
    my $saved = POSIX::Termios->new;
    $saved->getattr(fileno(STDIN));

    my $tio = POSIX::Termios->new;
    $tio->getattr(fileno(STDIN));
    my $lflag = $tio->getlflag;
    $tio->setlflag($lflag & ~(ECHO | ICANON));   # disable line buffering and echo
    $tio->setcc(VMIN,  0);                       # non-blocking reads
    $tio->setcc(VTIME, 0);
    $tio->setattr(fileno(STDIN), TCSANOW);

    return $saved;
}

sub tui_term_restore {
    my ($saved) = @_;
    $saved->setattr(fileno(STDIN), TCSANOW) if $saved;
}

# ------------------------------------------------------------------------------
# tui_read_key - non-blocking single-keystroke reader.
# Returns one of: 'left', 'right', 'up', 'down', a literal one-character
# string ('q', '5', etc.), or undef if no input was ready within $timeout.
#
# Arrow keys arrive as 3-byte escape sequences (e.g. ESC '[' 'A'), so we
# read up to 8 bytes at a time and pattern-match.
# ------------------------------------------------------------------------------
sub tui_read_key {
    my ($timeout) = @_;

    my $rin = '';
    vec($rin, fileno(STDIN), 1) = 1;             # add STDIN to the read set
    my $ready = select($rin, undef, undef, $timeout);
    return undef unless $ready;

    my $buf = '';
    my $n = sysread(STDIN, $buf, 8);
    return undef if !defined $n || $n == 0;

    return 'left'  if $buf eq "\e[D";
    return 'right' if $buf eq "\e[C";
    return 'up'    if $buf eq "\e[A";
    return 'down'  if $buf eq "\e[B";
    return 'esc'   if $buf eq "\e";
    return $buf;                                  # single char (or other)
}

# ------------------------------------------------------------------------------
# tui_term_size - ask the terminal how big it is. Falls back to 80x24 if
# stty isn't available. We don't use any user-controlled args here so the
# backtick is safe.
# ------------------------------------------------------------------------------
sub tui_term_size {
    my $size = `stty size 2>/dev/null`;
    return (24, 80) unless defined $size && length $size;
    chomp $size;
    my ($rows, $cols) = split /\s+/, $size;
    return ($rows || 24, $cols || 80);
}

# ------------------------------------------------------------------------------
# tui_start_mpv - fork+exec mpv as a background child with its stdio
# redirected to /dev/null (so it can't write over our TUI). Returns the
# child's PID via the state hash.
# ------------------------------------------------------------------------------
sub tui_start_mpv {
    my ($st) = @_;

    my ($name, $url) = split /::/, $st->{stations}[$st->{current}], 2;
    verbose_log("TUI: Starting mpv for station '$name' at URL: $url");

    # If mpv left a stale socket from a previous run, clear it.
    unlink $st->{sock} if -e $st->{sock};

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        # CHILD: detach from terminal stdio, then exec mpv. We use POSIX::_exit
        # on failure so we don't run any END blocks belonging to the parent.
        open(STDIN,  '<', '/dev/null');
        open(STDOUT, '>', '/dev/null');
        # Keep stderr open if verbose logging is enabled
        open(STDERR, '>', '/dev/null') unless $VERBOSE;

        my @args = (
            'mpv',
            '--no-video',
            '--no-terminal',                      # tells mpv to not try to drive the tty
            '--display-tags=',
            '--msg-level=all=error',
            "--input-ipc-server=$st->{sock}",
        );
        if ($st->{filter}) {
            push @args, '--af=lavfi=[highpass=f=300,lowpass=f=4500,acompressor]';
        }
        push @args, $url;

        # exec() never returns on success; the 'or' branch only runs if exec
        # itself fails (e.g. mpv not on PATH despite our earlier check).
        exec(@args) or POSIX::_exit(127);
    }

    $st->{mpv_pid}    = $pid;
    $st->{track}      = '';
    $st->{last_poll}  = 0;
    $st->{tune_start} = time();
    verbose_log("TUI: mpv started with PID: $pid");
}

# ------------------------------------------------------------------------------
# tui_stop_mpv - politely SIGTERM mpv, then escalate to SIGKILL if it doesn't
# die within ~1 second. Either way, reap the zombie and remove the socket.
# ------------------------------------------------------------------------------
sub tui_stop_mpv {
    my ($st) = @_;
    my $pid = $st->{mpv_pid};
    return unless $pid;

    verbose_log("TUI: Stopping mpv process PID: $pid");
    kill 'TERM', $pid;
    for (1 .. 20) {                               # wait up to ~1s (20 * 50ms)
        my $r = waitpid($pid, WNOHANG);
        if ($r == $pid || $r == -1) {
            $st->{mpv_pid} = undef;
            unlink $st->{sock} if -e $st->{sock};
            verbose_log("TUI: mpv stopped gracefully");
            return;
        }
        sleep 0.05;
    }

    # Still alive - SIGKILL it.
    verbose_log("TUI: mpv didn't respond to SIGTERM, sending SIGKILL");
    kill 'KILL', $pid;
    waitpid($pid, 0);
    $st->{mpv_pid} = undef;
    unlink $st->{sock} if -e $st->{sock};
    verbose_log("TUI: mpv killed and socket cleaned up");
}

# ------------------------------------------------------------------------------
# tui_query_track - one-shot fetch of the current ICY title. Returns undef
# if mpv isn't ready yet, has no metadata, or the IPC call timed out.
# ------------------------------------------------------------------------------
sub tui_query_track {
    my ($st) = @_;
    return undef unless -S $st->{sock};
    return ipc_get_property(
        $st->{sock},
        'metadata/icy-title',
        $st->{req_id}++,
        0.3,
    );
}

# ------------------------------------------------------------------------------
# tui_change / tui_jump - station-change helpers. Both stop mpv, advance the
# index, then start mpv again. tui_change cycles by +/-1; tui_jump goes
# straight to a specific 0-based index.
# ------------------------------------------------------------------------------
sub tui_change {
    my ($st, $delta) = @_;
    my $n = scalar @{ $st->{stations} };
    return if $n == 0;
    # Perl's % gives non-negative results for positive divisors, so
    # (-1) % 5 == 4 - exactly what we want for wraparound.
    $st->{current} = ($st->{current} + $delta) % $n;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    $st->{msg}       = 'Tuning…';
    $st->{msg_until} = time() + 1.2;
}

sub tui_jump {
    my ($st, $idx) = @_;
    return if $idx < 0 || $idx >= scalar @{ $st->{stations} };
    return if $idx == $st->{current};
    $st->{current} = $idx;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    $st->{msg}       = 'Tuning…';
    $st->{msg_until} = time() + 1.2;
}

sub tui_toggle_filter {
    my ($st) = @_;
    $st->{filter} = $st->{filter} ? 0 : 1;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    $st->{msg}       = $st->{filter} ? 'Lo-Fi filter ON'  : 'Lo-Fi filter OFF';
    $st->{msg_until} = time() + 1.5;
}

sub tui_retune {
    my ($st) = @_;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    $st->{msg}       = 'Re-tuning…';
    $st->{msg_until} = time() + 1.2;
}

# ------------------------------------------------------------------------------
# tui_dump_stream_info - Display verbose stream information as an overlay in
# TUI mode. This shows detailed metadata about the current stream including
# ICY tags, bitrate, codec, and track info. The display pauses playback UI
# and waits for any keypress to dismiss and return to normal TUI.
# ------------------------------------------------------------------------------
sub tui_dump_stream_info {
    my ($st) = @_;

    my ($name, $url) = split /::/, $st->{stations}[$st->{current}], 2;

    # Clear screen and move to top
    print "\e[2J\e[H";

    # Header
    print "${BOLD}${CYAN}";
    print "=" x 70 . "\n";
    print "Stream Information\n";
    print "=" x 70 . "\n";
    print "${RESET}\n";

    # Station info
    print "${BOLD}Station Name:${RESET} $name\n";
    print "${BOLD}Stream URL:${RESET}   $url\n";
    print "${BOLD}Current Track:${RESET} " . ($st->{track} || '(no track info)') . "\n";
    print "\n";

    # Get detailed metadata from mpv via IPC if available
    if ($st->{mpv_pid} && -S $st->{sock}) {
        print "${CYAN}--- ICY/Metadata Tags (from mpv) ---${RESET}\n";

        my $req_id = $st->{req_id}++;
        my @props = (
            ['metadata/icy-name',        'Station Name'],
            ['metadata/icy-title',       'Track Title'],
            ['metadata/icy-genre',       'Genre'],
            ['metadata/icy-br',          'Bitrate (kbps)'],
            ['metadata/icy-description', 'Description'],
            ['metadata/icy-url',         'Homepage URL'],
        );

        my $has_metadata = 0;
        for my $prop (@props) {
            my ($key, $label) = @$prop;
            my $value = ipc_get_property($st->{sock}, $key, $req_id++, 0.3);
            if (defined $value && length $value) {
                printf "  ${DIM}%-20s${RESET} %s\n", "$label:", $value;
                $has_metadata = 1;
            }
        }
        if (!$has_metadata) {
            print "  ${DIM}(No ICY metadata available)${RESET}\n";
        }
        print "\n";
    }

    # Get detailed format info from ffprobe if available
    if (system("command -v ffprobe > /dev/null 2>&1") == 0) {
        print "${CYAN}--- Deep Stream Analysis (ffprobe) ---${RESET}\n";

        my $probe = run_capture(
            'ffprobe',
            '-v', 'quiet',
            '-timeout', '5000000',
            '-show_entries', 'format:format_tags:stream',
            '-of', 'default=noprint_wrappers=1',
            $url,
        );

        if (defined $probe && length $probe) {
            # Parse and display in a more readable format
            for my $line (split /\n/, $probe) {
                if ($line =~ /^\[(\w+)\]/) {
                    print "${GREEN}[$1]${RESET}\n";
                } elsif ($line =~ /^TAG:(.+)=(.+)$/) {
                    printf "  ${DIM}%-20s${RESET} %s\n", "$1:", $2;
                } elsif ($line =~ /^(\w+)=(.+)$/) {
                    printf "  ${DIM}%-20s${RESET} %s\n", "$1:", $2;
                }
            }
        } else {
            print "  ${DIM}(No additional metadata available)${RESET}\n";
        }
        print "\n";
    }

    # Footer
    print "${BOLD}${CYAN}";
    print "=" x 70 . "\n";
    print "${RESET}";
    print "${YELLOW}Press any key to return to radio...${RESET}\n";

    # Wait for any keypress (blocking read)
    my $saved_term = tui_term_setup();  # Ensure raw mode
    tui_read_key(undef);  # Blocking read (no timeout)
    tui_term_restore($saved_term);

    # Clear screen and return - the main loop will redraw the TUI
    print "\e[2J\e[H";

    verbose_log("TUI: Stream info displayed and dismissed");
}

# ------------------------------------------------------------------------------
# tui_fake_freq - turn a station index into a fake AM-band frequency for the
# display. Real AM band: 540 kHz to 1700 kHz. Just visual flavour.
# ------------------------------------------------------------------------------
sub tui_fake_freq {
    my ($idx, $total) = @_;
    return 1020 if $total <= 1;
    my $f = 540 + int($idx * (1700 - 540) / ($total - 1) + 0.5);
    # Round to the nearest 10 kHz channel for that vintage AM feel.
    return int(($f + 5) / 10) * 10;
}

# ------------------------------------------------------------------------------
# pad_to / truncate_to - padding helpers that count CHARACTERS not bytes.
# Required because length() on a string with ANSI codes overcounts width,
# and length() on a UTF-8 byte string would too. Inputs here must be plain
# (no ANSI) under 'use utf8;'.
# ------------------------------------------------------------------------------
sub pad_to {
    my ($s, $w) = @_;
    my $l = length $s;
    return $s . (' ' x ($w - $l)) if $l < $w;
    return substr($s, 0, $w);
}

sub truncate_to {
    my ($s, $w) = @_;
    return $s if length($s) <= $w;
    return substr($s, 0, $w - 1) . '…';
}

# ------------------------------------------------------------------------------
# Drawing primitives. Each row of the TUI is exactly $TUI_INNER (64) chars
# wide INSIDE the borders. We build the row as plain text first, then wrap
# with the border chars. ANSI color codes are added as prefixes/suffixes
# around specific spans - they don't count toward visible width.
# ------------------------------------------------------------------------------

# Center a body string inside an inner-width space, return the padded string
sub centered {
    my ($s, $w) = @_;
    my $extra = $w - length($s);
    return $s if $extra <= 0;
    my $left  = int($extra / 2);
    my $right = $extra - $left;
    return (' ' x $left) . $s . (' ' x $right);
}

# Build the title bar (row 1): "  <centered AM_RADIO>  [Lo-Fi:XXX] "
# The brand is centered in the available space; the Lo-Fi badge sits flush right.
sub tui_title_row {
    my ($st) = @_;

    my $brand  = 'AM_RADIO';     # 8 visible chars
    my $filter = $st->{filter} ? '[Lo-Fi:ON ]'   # 11 visible chars (trailing space keeps width)
                               : '[Lo-Fi:OFF]';

    # Inner width = 64. Right segment: 11 (filter) + 1 (trailing space) = 12.
    # Left segment: 1 (leading space). Brand field: 64 - 1 - 12 = 51 chars.
    # centered() pads $brand symmetrically inside the 51-char field.
    my $body = ' ' . centered($brand, 51) . $filter . ' ';

    # Sanity check: keeps us honest if someone tweaks a constant.
    die "title row width " . length($body) . " != $TUI_INNER" if length($body) != $TUI_INNER;

    # Colorize: bold yellow branding, dim/magenta filter badge.
    my $coloured = $body;
    $coloured =~ s/AM_RADIO/${BOLD}${YELLOW}AM_RADIO$RESET/;
    if ($st->{filter}) {
        $coloured =~ s/\Q[Lo-Fi:ON ]/$MAGENTA${BOLD}[Lo-Fi:ON ]$RESET/;
    } else {
        $coloured =~ s/\Q[Lo-Fi:OFF]/${DIM}[Lo-Fi:OFF]$RESET/;
    }

    return $coloured;
}

# Station-info row 1: "   ► <name padded>          <freq> kHz   "
sub tui_info_row1 {
    my ($st) = @_;
    my (undef, undef) = (undef, undef);
    my ($name) = split /::/, $st->{stations}[$st->{current}], 2;
    my $freq   = tui_fake_freq($st->{current}, scalar @{ $st->{stations} });
    my $freq_label = sprintf '%4d kHz', $freq;     # 8 chars

    # Inner card width is 58 (the box uses 60, minus the two │ chars).
    # Layout: "│ ► " (4) + name (variable) + spaces + freq_label (8) + " │" (2)
    # Card visible width 60 includes the two │ chars; inner is 58.
    my $inner_card = 58;
    my $name_w     = $inner_card - 2 - 8 - 1;     # leave room for "► " and " freq"
    my $name_t     = truncate_to($name, $name_w);
    my $left       = '► ' . $name_t;
    my $pad        = $inner_card - length($left) - length($freq_label);
    $pad = 1 if $pad < 1;
    my $card_inner = $left . (' ' x $pad) . $freq_label;
    $card_inner = pad_to($card_inner, $inner_card);

    # Wrap with "│" and the outer 3-space margin so the whole thing is exactly 64
    # wide: "   │" (4) + 58 + "│ " (2) = 64.
    my $body = '   │' . $card_inner . '│ ';
    die "info1 width " . length($body) . " != $TUI_INNER" if length($body) != $TUI_INNER;

    # Colors
    my $coloured = $body;
    $coloured =~ s/►/${GREEN}${BOLD}►$RESET/;
    $coloured =~ s/\Q$freq_label/$YELLOW$freq_label$RESET/;
    # Box chars
    $coloured =~ s/│/${CYAN}│$RESET/g;
    return $coloured;
}

# Station-info row 2: "   │ ♪ <track padded>                          │ "
sub tui_info_row2 {
    my ($st) = @_;
    my $track = $st->{track};
    my $display;
    if (defined $track && length $track) {
        $display = '♪ ' . truncate_to($track, 56 - 2);   # 56 = inner card minus a 2-char prefix slot
    } else {
        my $waiting = ($st->{tune_start} && time() - $st->{tune_start} < 5)
            ? '… tuning in …'
            : '(no track info)';
        $display = '♪ ' . $waiting;
    }
    my $inner_card = 58;
    my $card_inner = pad_to($display, $inner_card);

    my $body = '   │' . $card_inner . '│ ';
    die "info2 width " . length($body) . " != $TUI_INNER" if length($body) != $TUI_INNER;

    my $coloured = $body;
    $coloured =~ s/♪/${GREEN}♪$RESET/;
    $coloured =~ s/\(no track info\)/${DIM}(no track info)$RESET/;
    $coloured =~ s/… tuning in …/${YELLOW}… tuning in …$RESET/;
    $coloured =~ s/│/${CYAN}│$RESET/g;
    return $coloured;
}

# Top, bottom edges of the station-info card
sub tui_card_top {
    my $body = '   ┌' . ('─' x 58) . '┐ ';
    return "${CYAN}${body}${RESET}";
}
sub tui_card_bot {
    my $body = '   └' . ('─' x 58) . '┘ ';
    return "${CYAN}${body}${RESET}";
}

# Frequency dial: needle, line, ticks, labels.
# Each call returns a single row.
sub tui_dial_needle_row {
    my ($st) = @_;
    my $n = scalar @{ $st->{stations} };
    my $cur = $st->{current};

    # Needle's column inside the dial (0..DIAL_WIDTH-1)
    my $pos;
    if ($n <= 1) {
        $pos = int($TUI_DIAL_WIDTH / 2);
    } else {
        $pos = int($cur * ($TUI_DIAL_WIDTH - 1) / ($n - 1) + 0.5);
    }

    my $body = (' ' x ($TUI_DIAL_LEFT + $pos))
             . '▼'
             . (' ' x ($TUI_INNER - $TUI_DIAL_LEFT - $pos - 1));
    die "needle row width" if length($body) != $TUI_INNER;

    my $coloured = $body;
    $coloured =~ s/▼/${YELLOW}${BOLD}▼$RESET/;
    return $coloured;
}

sub tui_dial_line_row {
    my $body = (' ' x $TUI_DIAL_LEFT)
             . ('━' x $TUI_DIAL_WIDTH)
             . (' ' x ($TUI_INNER - $TUI_DIAL_LEFT - $TUI_DIAL_WIDTH));
    die "dial line width" if length($body) != $TUI_INNER;
    # Color the bar
    my $coloured = $body;
    $coloured =~ s/(━+)/$CYAN$1$RESET/;
    return $coloured;
}

sub tui_dial_tick_row {
    my ($st) = @_;
    my $n = scalar @{ $st->{stations} };
    my $cur = $st->{current};

    # Build an array, one slot per dial column. Default to a thin space.
    my @slots = (' ') x $TUI_DIAL_WIDTH;

    # Place a faint tick for every station, then overdraw the current one.
    for my $i (0 .. $n - 1) {
        next if $i == $cur;
        my $p = $n <= 1 ? int($TUI_DIAL_WIDTH/2)
                        : int($i * ($TUI_DIAL_WIDTH - 1) / ($n - 1) + 0.5);
        $p = 0 if $p < 0;
        $p = $TUI_DIAL_WIDTH - 1 if $p > $TUI_DIAL_WIDTH - 1;
        $slots[$p] = "${DIM}${CYAN}╎${RESET}";
    }
    # Current station's tick: bright and bold.
    my $p_cur = $n <= 1 ? int($TUI_DIAL_WIDTH/2)
                        : int($cur * ($TUI_DIAL_WIDTH - 1) / ($n - 1) + 0.5);
    $p_cur = 0 if $p_cur < 0;
    $p_cur = $TUI_DIAL_WIDTH - 1 if $p_cur > $TUI_DIAL_WIDTH - 1;
    $slots[$p_cur] = "${YELLOW}${BOLD}│${RESET}";

    # We can't use length() on the assembled string anymore (it has ANSI in
    # it), so build the visible-width prefix and suffix as plain spaces.
    my $body = (' ' x $TUI_DIAL_LEFT)
             . join('', @slots)
             . (' ' x ($TUI_INNER - $TUI_DIAL_LEFT - $TUI_DIAL_WIDTH));
    return $body;
}

# Frequency labels under the dial. Hand-tuned for $TUI_DIAL_WIDTH == 56.
# Real AM channels at 540, 720, 900, 1080, 1260, 1440, 1620, 1700.
sub tui_dial_label_row {
    # Place each label so its first char sits at an evenly-spaced position
    # along the dial. With 8 labels and width 56, spacing is 8 chars.
    my @labels = ('540', '720', '900', '1080', '1260', '1440', '1620', '1700');
    my @slots = (' ') x $TUI_DIAL_WIDTH;
    for my $li (0 .. $#labels) {
        my $pos = int($li * ($TUI_DIAL_WIDTH - 4) / $#labels);
        my $lab = $labels[$li];
        for my $ci (0 .. length($lab) - 1) {
            my $p = $pos + $ci;
            $slots[$p] = substr($lab, $ci, 1) if $p < $TUI_DIAL_WIDTH;
        }
    }
    my $body = (' ' x $TUI_DIAL_LEFT)
             . join('', @slots)
             . (' ' x ($TUI_INNER - $TUI_DIAL_LEFT - $TUI_DIAL_WIDTH));
    die "label row width" if length($body) != $TUI_INNER;
    # Trailing "kHz" tag would push us off-edge; we put it on the same row as
    # the label by overwriting the very last 4 visible chars.
    substr($body, $TUI_INNER - 5, 4) = ' kHz';
    my $coloured = $body;
    $coloured =~ s/(\d+)/$DIM$1$RESET/g;
    $coloured =~ s/kHz/${DIM}${CYAN}kHz$RESET/;
    return $coloured;
}

# Preset buttons: 1..min(9, n_stations), current station highlighted in brackets.
# The signal meter has been removed; only presets are shown, centered.
sub tui_status_row {
    my ($st) = @_;

    # Build the preset button strip. The active station shows as [N], others as " N ".
    my $n = scalar @{ $st->{stations} };
    my $max_preset = $n > 9 ? 9 : $n;
    my @cells;
    for my $i (1 .. $max_preset) {
        push @cells, ($i - 1 == $st->{current}) ? "[$i]" : " $i ";
    }
    my $presets = join('', @cells);

    # Center the entire "PRESETS N N …" block inside the 64-char inner width.
    my $body = pad_to(centered("PRESETS  $presets", $TUI_INNER), $TUI_INNER);

    my $coloured = $body;
    $coloured =~ s/PRESETS/${BOLD}PRESETS$RESET/;
    # Highlight the active preset with yellow bold brackets
    $coloured =~ s/\[(\d)\]/${YELLOW}${BOLD}[$1]$RESET/g;
    return $coloured;
}

# Status / message line. Shows the transient message ("Tuning…", "Lo-Fi ON")
# when one is active; otherwise blank.
sub tui_msg_row {
    my ($st) = @_;
    my $msg = '';
    if ($st->{msg} && time() < $st->{msg_until}) {
        $msg = '> ' . $st->{msg};
    }
    my $body = pad_to('   ' . $msg, $TUI_INNER);
    my $coloured = $body;
    $coloured =~ s/^(\s*> )/${YELLOW}$1$RESET/;
    return $coloured;
}

# Footer / help line — one-line summary of all key bindings
sub tui_help_row {
    my $body = '  ◀ ▶ tune   1-9 preset   o lo-fi   i info   r retune   f find   q quit  ';
    $body = pad_to($body, $TUI_INNER);
    my $coloured = $body;
    $coloured =~ s/(◀ ▶|1-9|o|i|r|f|q)/${CYAN}$1$RESET/g;
    return $coloured;
}

# Pure-cosmetic empty interior row
sub tui_blank_row {
    return ' ' x $TUI_INNER;
}

# ------------------------------------------------------------------------------
# tui_search_help_row - key-binding bar shown at the bottom while in search mode.
# Replaces the normal tui_help_row when $st->{search_mode} is active.
# ------------------------------------------------------------------------------
sub tui_search_help_row {
    my ($mode) = @_;
    my $body = $mode == 1
        ? '  Enter=search    1-9 tune & save    Esc=cancel'
        : '  1-9 tune & save    Esc=cancel';
    $body = pad_to($body, $TUI_INNER);
    my $coloured = $body;
    $coloured =~ s/(Enter|1-9|Esc)/${CYAN}$1$RESET/g;
    return $coloured;
}

# ------------------------------------------------------------------------------
# tui_search_content_rows - returns the 15 inner content rows (rows 3-17) that
# replace the normal station/dial layout while search mode is active.
#
# Row mapping:
#   0 (row 3)  blank
#   1 (row 4)  card top border
#   2 (row 5)  search prompt card row  ("Search: [query]_")
#   3 (row 6)  card bottom border
#   4 (row 7)  blank
#   5 (row 8)  status/instruction line
#   6-10       up to 5 search result rows  (blank if slot is empty)
#   11(row 14) blank
#   12(row 15) preset buttons (unchanged — music keeps playing)
#   13(row 16) blank
#   14(row 17) transient message row
# ------------------------------------------------------------------------------
sub tui_search_content_rows {
    my ($st) = @_;

    my $mode    = $st->{search_mode};
    my $query   = $st->{search_query} // '';
    my @results = @{ $st->{search_results} // [] };

    # ---- Search prompt card row ------------------------------------------
    # The card is 60 chars wide (3-space margin + │ + 58 content + │ + space).
    my $inner_card  = 58;
    my $label       = 'Search: ';                          # 8 visible chars
    my $max_q_w     = $inner_card - length($label) - 1;   # reserve 1 for cursor '_'
    my $q_display   = truncate_to($query, $max_q_w);
    my $cursor      = $mode == 1 ? '_' : ' ';             # blinking cursor in typing state
    my $prompt_inner = pad_to($label . $q_display . $cursor, $inner_card);

    # Colorize the prompt: cyan label, bold cursor
    my $prompt_colored = $prompt_inner;
    $prompt_colored =~ s/Search:/${CYAN}Search:$RESET/;
    $prompt_colored =~ s/_$/${BOLD}_$RESET/ if $mode == 1;

    # Wrap the prompt in card borders (same style as tui_card_top/bot)
    my $card_row = '   ' . "${CYAN}│$RESET" . $prompt_colored . "${CYAN}│$RESET" . ' ';

    # ---- Status / instruction line ----------------------------------------
    my $status_text;
    if ($mode == 1) {
        $status_text = length($query)
            ? "   Press Enter to search for \"$query\""
            : '   Type a station name and press Enter to search';
    } else {
        my $n = scalar @results;
        $status_text = $n
            ? sprintf('   Found %d station(s) — press 1-%d to tune in and save',
                      $n, $n > 9 ? 9 : $n)
            : '   No stations found. Try a different query.';
    }
    my $status = pad_to($status_text, $TUI_INNER);
    # Highlight the key-range hint if present
    (my $status_colored = $status) =~ s/(\d+-\d+)/${CYAN}$1$RESET/;

    # ---- Result rows (5 slots) -------------------------------------------
    # Each result row: "   N) <name padded to fill>  NNN kbps"
    my @result_rows;
    for my $i (0 .. 4) {
        my $r = $results[$i];
        if (defined $r) {
            my $num_str = sprintf '%d) ', $i + 1;          # "N) " = 3 chars
            my $bitrate = $r->{bitrate}
                ? sprintf('%3d kbps', $r->{bitrate})       # "NNN kbps" = 8 chars
                : '        ';                               # 8 spaces when unknown
            my $prefix  = '   ' . $num_str;                # "   N) " = 6 chars
            my $suffix  = '  ' . $bitrate;                 # "  NNN kbps" = 10 chars
            my $name_w  = $TUI_INNER - length($prefix) - length($suffix);
            my $name_t  = truncate_to($r->{name} // '', $name_w);
            my $body    = $prefix . pad_to($name_t, $name_w) . $suffix;
            $body       = pad_to($body, $TUI_INNER);

            my $colored = $body;
            $colored =~ s/^(\s+\d+\) )/${CYAN}$1$RESET/;  # cyan result number
            $colored =~ s/(\d+ kbps)/$YELLOW$1$RESET/;    # yellow bitrate
            push @result_rows, $colored;
        } else {
            push @result_rows, tui_blank_row();            # empty slot
        }
    }

    # ---- Assemble and return 15 content rows (rows 3-17) -----------------
    return (
        tui_blank_row(),       # row 3:  blank padding before the card
        tui_card_top(),        # row 4:  ┌──────────────────────────────────┐
        $card_row,             # row 5:  │ Search: [query]_                 │
        tui_card_bot(),        # row 6:  └──────────────────────────────────┘
        tui_blank_row(),       # row 7:  blank
        $status_colored,       # row 8:  instructions / result count
        @result_rows,          # rows 9-13: up to 5 search results (or blanks)
        tui_blank_row(),       # row 14: blank
        tui_status_row($st),   # row 15: preset buttons (unchanged during search)
        tui_blank_row(),       # row 16: blank
        tui_msg_row($st),      # row 17: transient messages ("Searching…" etc.)
    );
}


# ------------------------------------------------------------------------------
# tui_draw - assemble all rows and flush them to the screen in one pass.
#
# Every content row is exactly $TUI_INNER (64) visible characters wide; the
# outer border glyphs (║, ╔, ╚ …) are added here as the array is built.
# The cursor is moved to the top-left corner (ESC[H) before printing so the
# entire panel is redrawn in-place rather than scrolling.  ESC[K at the end
# of each line clears any leftover characters from a wider previous frame.
# ------------------------------------------------------------------------------
sub tui_draw {
    my ($st) = @_;

    # Assemble all 21 rows (indices 0-20) into an array.  In search mode the
    # content rows (3-17) and the help row (19) are swapped out below.
    my @rows = (
        # Row 0: Top outer border spanning the full TUI_WIDTH (66 columns)
        "${CYAN}╔" . ('═' x $TUI_INNER) . "╗${RESET}",

        # Row 1: Title bar — AM_RADIO branding centred, Lo-Fi badge on the right
        "${CYAN}║${RESET}" . tui_title_row($st)        . "${CYAN}║${RESET}",

        # Row 2: Horizontal divider between the title and the content area
        "${CYAN}╠" . ('═' x $TUI_INNER) . "╣${RESET}",

        # Row 3: Blank padding row at the top of the content area
        "${CYAN}║${RESET}" . tui_blank_row()            . "${CYAN}║${RESET}",

        # Row 4: Top edge of the station-info card (┌───┐)
        "${CYAN}║${RESET}" . tui_card_top()             . "${CYAN}║${RESET}",

        # Row 5: Station name and its fake AM frequency inside the card
        "${CYAN}║${RESET}" . tui_info_row1($st)         . "${CYAN}║${RESET}",

        # Row 6: Current track title (or "tuning in…" placeholder) inside the card
        "${CYAN}║${RESET}" . tui_info_row2($st)         . "${CYAN}║${RESET}",

        # Row 7: Bottom edge of the station-info card (└───┘)
        "${CYAN}║${RESET}" . tui_card_bot()             . "${CYAN}║${RESET}",

        # Row 8: Blank row separating the card from the frequency dial section
        "${CYAN}║${RESET}" . tui_blank_row()            . "${CYAN}║${RESET}",

        # Row 9: "FREQUENCY" section label
        "${CYAN}║${RESET}" . pad_to('   FREQUENCY', $TUI_INNER) . "${CYAN}║${RESET}",

        # Row 10: Dial needle (▼) positioned proportionally for the current station
        "${CYAN}║${RESET}" . tui_dial_needle_row($st)   . "${CYAN}║${RESET}",

        # Row 11: Horizontal dial track (━━━━━━━━━━━━)
        "${CYAN}║${RESET}" . tui_dial_line_row()        . "${CYAN}║${RESET}",

        # Row 12: Tick marks — dim for unselected stations, bold for current
        "${CYAN}║${RESET}" . tui_dial_tick_row($st)     . "${CYAN}║${RESET}",

        # Row 13: Frequency labels (540 – 1700 kHz) with "kHz" unit on the right
        "${CYAN}║${RESET}" . tui_dial_label_row()       . "${CYAN}║${RESET}",

        # Row 14: Blank row between the dial and the preset buttons
        "${CYAN}║${RESET}" . tui_blank_row()            . "${CYAN}║${RESET}",

        # Row 15: Preset buttons 1-9; the active station is highlighted as [N]
        "${CYAN}║${RESET}" . tui_status_row($st)        . "${CYAN}║${RESET}",

        # Row 16: Blank row between presets and the transient message line
        "${CYAN}║${RESET}" . tui_blank_row()            . "${CYAN}║${RESET}",

        # Row 17: Transient message row ("Tuning…", "Lo-Fi ON", etc.)
        "${CYAN}║${RESET}" . tui_msg_row($st)           . "${CYAN}║${RESET}",

        # Row 18: Horizontal divider between the content area and the help row
        "${CYAN}╠" . ('═' x $TUI_INNER) . "╣${RESET}",

        # Row 19: Key-binding summary — one line listing all available commands
        "${CYAN}║${RESET}" . tui_help_row()             . "${CYAN}║${RESET}",

        # Row 20: Bottom outer border
        "${CYAN}╚" . ('═' x $TUI_INNER) . "╝${RESET}",
    );

    # In search mode, overlay the content area (rows 3-17) with the search UI
    # and replace the help row (19) with search-specific key bindings.
    # The outer borders (0-2, 18, 20) and the title (1) are unchanged.
    if ($st->{search_mode}) {
        my @content = tui_search_content_rows($st);
        for my $i (0 .. $#content) {
            $rows[3 + $i] = "${CYAN}║${RESET}" . $content[$i] . "${CYAN}║${RESET}";
        }
        $rows[19] = "${CYAN}║${RESET}" . tui_search_help_row($st->{search_mode})
                  . "${CYAN}║${RESET}";
    }

    # Move the cursor to the top-left corner (home position) and redraw every
    # row in sequence.  ESC[K erases to end of line so any characters from a
    # wider previous frame or a terminal resize artefact are cleaned up.
    print "\e[H";
    for my $row (@rows) {
        print $row, "\e[K\n";
    }
    # ESC[J clears from the cursor to the bottom of the screen.  This removes
    # any content that was below our TUI (e.g. from a previous taller layout
    # or text that was on screen before we entered alternate-screen mode).
    print "\e[J";
}

# ------------------------------------------------------------------------------
# tui_do_search - call the Radio-Browser.info API and populate search results.
#
# This is a blocking network call (curl).  The music keeps playing because mpv
# runs as a separate child process and is not affected by the parent blocking.
# We redraw the TUI with a "Searching…" message before the call so the user
# gets feedback immediately rather than staring at a frozen screen.
# ------------------------------------------------------------------------------
sub tui_do_search {
    my ($st) = @_;
    my $query = $st->{search_query} // '';
    return unless length $query;

    # Show a "Searching…" message and flush to the terminal before we block.
    $st->{msg}       = 'Searching…';
    $st->{msg_until} = time() + 30;
    tui_draw($st);

    my $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                . '?name=' . uri_escape($query)
                . '&limit=9&hidebroken=true&order=votes&reverse=true';

    # run_capture uses list-form exec so the query string can never be
    # misinterpreted as shell code even if it contains metacharacters.
    my $response = run_capture('curl', '-sL', '--max-time', '8', $api_url);
    my $data     = eval { decode_json($response // '') };

    if ($@ || ref($data) ne 'ARRAY') {
        $st->{search_results} = [];
        $st->{msg}            = 'Search failed — check network connection';
        $st->{msg_until}      = time() + 3;
    } else {
        # Normalise into a plain list of {name, url, bitrate} hashes.
        $st->{search_results} = [
            map { {
                name    => $_->{name}    // '',
                url     => $_->{url}     // '',
                bitrate => $_->{bitrate} // 0,
            } }
            @$data
        ];
        my $n = scalar @{ $st->{search_results} };
        $st->{msg}       = $n ? "Found $n match(es)" : 'No stations found';
        $st->{msg_until} = time() + 2;
    }

    # Advance to results-display state so the user can pick a station.
    $st->{search_mode} = 2;
}

# ------------------------------------------------------------------------------
# tui_search_select - save a search result to ~/.radio_stations and tune mpv
# to it without stopping playback of the current stream first.
# ------------------------------------------------------------------------------
sub tui_search_select {
    my ($st, $n) = @_;   # $n is 1-based choice from the result list
    my @results = @{ $st->{search_results} // [] };
    my $idx = $n - 1;
    return if $idx < 0 || $idx >= @results;

    my $r    = $results[$idx];
    my $name = $r->{name} // '';
    my $url  = $r->{url}  // '';
    return unless length $name && length $url;

    # Strip any embedded newlines that a malformed API response might carry;
    # the config file format uses one "Name::URL" entry per line.
    $name =~ s/[\r\n]+/ /g;
    $url  =~ s/[\r\n]+//g;

    # Persist the chosen station so it appears in future sessions.
    if (open(my $fh, '>>', $CONFIG_FILE)) {
        print $fh $name . '::' . $url . "\n";
        close $fh;
    }

    # Hot-add the station to the in-memory list and switch mpv to it.
    push @STATIONS, $name . '::' . $url;
    $st->{stations} = \@STATIONS;
    $st->{current}  = $#STATIONS;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    $st->{msg}       = 'Tuning to ' . truncate_to($name, 30);
    $st->{msg_until} = time() + 2;

    # Clear search state and return to normal playback view.
    $st->{search_mode}    = 0;
    $st->{search_query}   = '';
    $st->{search_results} = [];
}



# ------------------------------------------------------------------------------
# radio_tui - main TUI driver.
# ------------------------------------------------------------------------------
sub radio_tui {
    my ($initial_idx, $initial_filter) = @_;

    if (@STATIONS == 0) {
        print STDERR "${YELLOW}No stations configured.${RESET}\n";
        return;
    }

    # Record the initial terminal size.  The startup check is strict (exit if
    # too small); subsequent resize handling is done in the event loop.
    my ($rows, $cols) = tui_term_size();
    if ($rows < $TUI_HEIGHT || $cols < $TUI_WIDTH) {
        print STDERR "${YELLOW}Terminal is ${cols}x${rows}; need at least ${TUI_WIDTH}x${TUI_HEIGHT}.${RESET}\n";
        exit 1;
    }

    my %st = (
        stations      => \@STATIONS,
        current       => ($initial_idx // 0),
        track         => '',
        filter        => $initial_filter ? 1 : 0,
        mpv_pid       => undef,
        sock          => "/tmp/am_radio_tui_$$.sock",
        last_poll     => 0,
        msg           => '',
        msg_until     => 0,
        tune_start    => 0,
        req_id        => 1,
        # Search mode state (see tui_do_search / tui_search_select)
        search_mode    => 0,   # 0=off  1=typing query  2=showing results
        search_query   => '',
        search_results => [],
    );

    my $saved_term = tui_term_setup();

    # Enter the alternate screen buffer so we don't clobber the user's
    # scrollback, then hide the cursor for cleaner drawing.
    print "\e[?1049h\e[?25l\e[2J\e[H";

    # Cleanup is idempotent (a flag prevents double-cleanup) and used by
    # both the normal exit path and the signal handlers.
    my $cleaned = 0;
    my $cleanup = sub {
        return if $cleaned++;
        tui_stop_mpv(\%st);
        tui_term_restore($saved_term);
        print "\e[?25h\e[?1049l";                 # show cursor, leave alt screen
    };
    local $SIG{INT}  = sub { $cleanup->(); exit 130; };
    local $SIG{TERM} = sub { $cleanup->(); exit 143; };
    local $SIG{HUP}  = sub { $cleanup->(); exit 129; };

    # SIGWINCH fires whenever the terminal window is resized.  We set a flag
    # here (signal-safe) and re-check terminal dimensions in the event loop.
    my $need_resize = 0;
    local $SIG{WINCH} = sub { $need_resize = 1; };

    tui_start_mpv(\%st);
    $st{msg}       = 'Tuning…';
    $st{msg_until} = time() + 1.5;

    # ---- main event loop --------------------------------------------------
    # Runs at roughly 20 Hz (tui_read_key blocks for up to 50ms per pass).
    # Each iteration:
    #   1. Handle terminal resize if SIGWINCH was received.
    #   2. Read a keystroke (non-blocking, 50ms timeout).
    #   3. If 1.5s have elapsed, re-fetch the ICY track title from mpv.
    #   4. Redraw the full panel.
    while (1) {

        # ---- Terminal resize handling -------------------------------------
        # On SIGWINCH, re-measure the terminal.  The stored $rows/$cols keep
        # their previous values until a new SIGWINCH triggers a fresh read,
        # so the too-small check below keeps firing (without extra stty calls)
        # until the user grows the window and SIGWINCH fires again.
        if ($need_resize) {
            $need_resize = 0;
            ($rows, $cols) = tui_term_size();
        }
        if ($rows < $TUI_HEIGHT || $cols < $TUI_WIDTH) {
            print "\e[2J\e[H";
            printf "${YELLOW}Terminal too small (%dx%d) — resize to at least %dx%d.${RESET}\n",
                   $cols, $rows, $TUI_WIDTH, $TUI_HEIGHT;
            print "Resize the terminal window to continue...\n";
            sleep 0.3;
            next;
        }

        # ---- Key handling ------------------------------------------------
        if (defined(my $key = tui_read_key(0.05))) {

            if ($st{search_mode}) {
                # -- Search mode --
                if ($key eq 'esc') {
                    # Cancel search and return to normal playback view
                    $st{search_mode}    = 0;
                    $st{search_query}   = '';
                    $st{search_results} = [];
                } elsif ($st{search_mode} == 2 && $key =~ /^[1-9]$/) {
                    # Result selection: save station and switch mpv to it
                    tui_search_select(\%st, int($key));
                } elsif ($st{search_mode} == 1) {
                    if ($key eq "\r") {
                        # Enter: run the blocking API search
                        tui_do_search(\%st);
                    } elsif ($key eq "\x7f" || $key eq "\x08") {
                        # Backspace / Delete: remove last character of query
                        $st{search_query} =~ s/.$//s;
                    } elsif (length($key) == 1 && $key =~ /[ -~]/) {
                        # Printable ASCII: accumulate into the search string
                        $st{search_query} .= $key;
                    }
                }
            } else {
                # -- Normal playback mode --
                if    ($key eq 'q' || $key eq 'Q' || $key eq 'esc')   { last }
                elsif ($key eq 'right' || $key eq 'n' || $key eq 'N') { tui_change(\%st, +1) }
                elsif ($key eq 'left'  || $key eq 'p' || $key eq 'P') { tui_change(\%st, -1) }
                elsif ($key =~ /^[1-9]$/)                             { tui_jump(\%st, $key - 1) }
                elsif ($key eq 'o' || $key eq 'O')                    { tui_toggle_filter(\%st) }
                elsif ($key eq 'r' || $key eq 'R')                    { tui_retune(\%st) }
                elsif ($key eq 'i' || $key eq 'I')                    { tui_dump_stream_info(\%st) }
                elsif ($key eq 'f' || $key eq '/')                    {
                    # Enter search mode — music is uninterrupted
                    $st{search_mode}    = 1;
                    $st{search_query}   = '';
                    $st{search_results} = [];
                }
            }
        }

        my $now = time();

        # Reap mpv if it died on its own (network drop, decoder crash, etc.)
        # so we don't keep showing stale track info.
        if ($st{mpv_pid} && waitpid($st{mpv_pid}, WNOHANG) == $st{mpv_pid}) {
            verbose_log("TUI: mpv process died unexpectedly (possible stream drop/crash)");
            $st{mpv_pid}   = undef;
            $st{msg}       = 'Stream lost — press r to retune';
            $st{msg_until} = $now + 5;
        }

        # Poll the ICY title from mpv every 1.5s.  We skip polling while in
        # search mode to avoid contending with the blocking search call.
        if ($now - $st{last_poll} >= 1.5 && $st{mpv_pid} && !$st{search_mode}) {
            my $t = tui_query_track(\%st);
            if (defined $t && $t ne $st{track}) {
                verbose_log("TUI: Track changed to: $t");
            }
            $st{track} = $t if defined $t;
            $st{last_poll} = $now;
        }

        tui_draw(\%st);
    }

    $cleanup->();
}


# ------------------------------------------------------------------------------
# load_afn_stations - Replace the current station list with American Forces
# Network (AFN) streaming stations. AFN provides radio and TV programming to
# U.S. military personnel and their families stationed around the world.
#
# This preset includes AFN stations from various global locations:
#   - AFN Pacific (Tokyo, Humphreys Korea)
#   - AFN Europe (Germany, Italy, Belgium, Bahrain)
#   - AFN locations (Guantanamo Bay, Turkey)
#
# Stream URLs are sourced from Radio-Browser.info verified working endpoints.
# All streams tested and confirmed operational as of January 2026.
# ------------------------------------------------------------------------------
sub load_afn_stations {
    print "${CYAN}Loading American Forces Network (AFN) stations...${RESET}\n";

    # Clear existing stations and load AFN presets
    @STATIONS = ();

    # AFN GO Tokyo (Japan) - 96 kbps MP3, 192 votes
    push @STATIONS, 'AFN GO Tokyo::http://22963.live.streamtheworld.com/AFNP_TKO_SC';

    # AFN 360 Guantanamo Bay (Cuba) - 96 kbps MP3, 1745 votes
    push @STATIONS, 'AFN 360 Guantanamo Bay::http://27783.live.streamtheworld.com:3690/AFNE_GMO_SC';

    # AFN GO Humphreys The Eagle (South Korea) - 32 kbps AAC+, 6 votes
    push @STATIONS, 'AFN GO Humphreys The Eagle::http://14993.live.streamtheworld.com/AFNP_OSNAAC_SC';

    # AFN 360 Bahrain (Bahrain) - 96 kbps MP3, 972 votes
    push @STATIONS, 'AFN 360 Bahrain::http://27863.live.streamtheworld.com/AFNE_BHN_SC';

    # AFN 360 Benelux (Belgium) - 96 kbps MP3, 31 votes
    push @STATIONS, 'AFN 360 Benelux::http://28993.live.streamtheworld.com:3690/AFNE_BLX_SC';

    # AFN İncirlik (Turkey) - 96 kbps MP3
    push @STATIONS, 'AFN İncirlik::https://playerservices.streamtheworld.com/api/livestream-redirect/AFNE_ICK.mp3';

    # AFN 360 Bavaria (Germany) - 96 kbps MP3, 102 votes
    push @STATIONS, 'AFN 360 Bavaria::http://28563.live.streamtheworld.com/AFNE_BAV_SC';

    # AFN 360 Vicenza (Italy) - 96 kbps MP3, 43 votes
    push @STATIONS, 'AFN 360 Vicenza::http://23543.live.streamtheworld.com/AFNE_VIC_SC';

    # AFN 360 Wiesbaden (Germany) - 96 kbps MP3, 130 votes
    push @STATIONS, 'AFN 360 Wiesbaden::http://25453.live.streamtheworld.com:3690/AFNE_WBN_SC';

    # AFN GO Bahrain (Bahrain) - 32 kbps AAC+, 306 votes
    push @STATIONS, 'AFN GO Bahrain::https://playerservices.streamtheworld.com/api/livestream-redirect/AFNE_BHNAAC.aac';

    my $count = scalar @STATIONS;
    print "${GREEN}Loaded $count AFN radio stations.${RESET}\n";
    print "${DIM}American Forces Network - Serving U.S. military worldwide${RESET}\n\n";
}


# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

my $STATION_CHOICE   = '';
my $FILTER_OLD_RADIO = 0;
my $SHOW_INFO        = 0;
my $TUI_MODE         = 0;
my $AFN_MODE         = 0;

# Check for --afn long option in ARGV before getopts processes anything
# This must happen before getopts because getopts doesn't handle long options
for my $i (reverse 0 .. $#ARGV) {
    if ($ARGV[$i] eq '--afn') {
        $AFN_MODE = 1;
        splice(@ARGV, $i, 1);  # Remove --afn from ARGV
    }
}

my %opts;
unless (getopts('s:f:loithv', \%opts)) {
    print STDERR "${YELLOW}Invalid option.${RESET}\n";
    show_help();
}

show_help() if $opts{h};

# If AFN mode is enabled, load AFN stations instead of the config file
if ($AFN_MODE) {
    load_afn_stations();
}

if ($opts{l}) {
    list_stations();
    exit 0;
}

discover_stations($opts{f}) if defined $opts{f};

$STATION_CHOICE   = $opts{s} if defined $opts{s};
$FILTER_OLD_RADIO = 1 if $opts{o};
$SHOW_INFO        = 1 if $opts{i};
$TUI_MODE         = 1 if $opts{t};
$VERBOSE          = 1 if $opts{v};

if ($STATION_CHOICE eq '' && @ARGV > 0) {
    $STATION_CHOICE = $ARGV[0];
}

# ==============================================================================
# MAIN SCRIPT LOGIC
# ==============================================================================

if (system("command -v mpv > /dev/null 2>&1") != 0) {
    print STDERR "Error: 'mpv' is required but not installed.\n";
    exit 1;
}

# ------------------------------------------------------------------------------
# TUI mode short-circuit: when -t is given, we hand off to the TUI driver
# and never come back to the classic flow.
# ------------------------------------------------------------------------------
if ($TUI_MODE) {
    my $start_idx = 0;
    if ($STATION_CHOICE ne '') {
        if ($STATION_CHOICE !~ /^\d+$/ || $STATION_CHOICE < 1 || $STATION_CHOICE > scalar @STATIONS) {
            print STDERR "${YELLOW}Invalid station number for -s.${RESET}\n";
            exit 1;
        }
        $start_idx = $STATION_CHOICE - 1;
    }
    radio_tui($start_idx, $FILTER_OLD_RADIO);
    exit 0;
}

# ------------------------------------------------------------------------------
# Classic flow: prompt for a station, then run mpv with a polling child.
# ------------------------------------------------------------------------------
if ($STATION_CHOICE eq '') {
    print "${BOLD}Select a station:${RESET}\n";
    list_stations();
    print "\nEnter station number: ";
    $STATION_CHOICE = <STDIN>;
    chomp $STATION_CHOICE if defined $STATION_CHOICE;
}

my $n = scalar @STATIONS;
if ($STATION_CHOICE !~ /^\d+$/ || $STATION_CHOICE < 1 || $STATION_CHOICE > $n) {
    print STDERR "${YELLOW}Error: Invalid selection. Please enter a number between 1 and $n.${RESET}\n";
    exit 1;
}

my ($STATION_NAME, $STATION_URL) = split /::/, $STATIONS[$STATION_CHOICE - 1], 2;

my $IPC_SOCKET = "/tmp/am_radio_$$.sock";

# Make sure a stray socket from a crashed previous run can't trip us up,
# and tidy up if we get killed before the explicit cleanup at the end.
unlink $IPC_SOCKET if -e $IPC_SOCKET;
END { unlink $IPC_SOCKET if defined $IPC_SOCKET && -e $IPC_SOCKET; }

my @MPV_ARGS = (
    '--no-video',
    '--display-tags=',
    '--msg-level=all=error',
    "--input-ipc-server=$IPC_SOCKET",
);

if ($FILTER_OLD_RADIO) {
    print "${YELLOW}[!] Lo-Fi AM Radio filter activated.${RESET}\n";
    push @MPV_ARGS, '--af=lavfi=[highpass=f=300,lowpass=f=4500,acompressor]';
}

dump_info($STATION_URL) if $SHOW_INFO;

verbose_log("Starting playback for station: $STATION_NAME");
verbose_log("Stream URL: $STATION_URL");

print "\n${BOLD}Tuning in to $STATION_NAME...${RESET}\n";
print "Press ${YELLOW}Ctrl+C${RESET} to stop playback.\n\n";

my $poller_pid = fork();
die "fork() failed: $!" unless defined $poller_pid;

if ($poller_pid == 0) {
    poll_track_loop($IPC_SOCKET);
    POSIX::_exit(0);
}

verbose_log("Starting mpv with args: " . join(' ', @MPV_ARGS));
my $mpv_exit = system('mpv', @MPV_ARGS, $STATION_URL);
verbose_log("mpv exited with status: $mpv_exit");

kill 'TERM', $poller_pid;
waitpid($poller_pid, 0);

unlink $IPC_SOCKET if -e $IPC_SOCKET;
verbose_log("Playback session ended, cleaned up IPC socket");

exit 0;

