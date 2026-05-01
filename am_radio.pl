#!/usr/bin/env perl

# ==============================================================================
# am_radio.pl - A command-line internet radio player
# ------------------------------------------------------------------------------
# Perl rewrite of the original am_radio.zsh script.
#
# What this script does:
#   * Plays internet radio streams via the external 'mpv' player
#   * Maintains a list of saved stations in ~/.radio_stations
#   * Discovers new stations via the public Radio-Browser.info API
#   * Optionally applies a lo-fi "old time AM radio" audio filter
#   * Optionally dumps stream metadata (ICY/ID3 tags) using 'ffprobe'
#
# External programs required at runtime:
#   * mpv      - to actually play the audio (mandatory)
#   * curl     - only needed for the -f (find) feature
#   * ffprobe  - only needed for the -i (info) feature
# ==============================================================================

use strict;            # Force variable declarations - catches typos at compile time
use warnings;          # Enable runtime warnings about suspicious constructs
use Getopt::Std;       # Core module for parsing single-letter command line options
use File::Basename;    # Provides basename() so we can show a clean script name
use JSON::PP;          # Pure-Perl JSON parser (core since 5.14) - replaces the 'jq' tool
use IO::Socket::UNIX;  # Unix-domain socket - for talking to mpv's IPC server
use POSIX ();          # Used for POSIX::_exit() in the child to skip cleanup blocks

# ==============================================================================
# CONFIGURATION & SETUP
# ==============================================================================

# Path to the user's saved-stations file. We pull HOME from the environment
# so this works on any user account. %ENV is Perl's hash of environment vars.
my $CONFIG_FILE = "$ENV{HOME}/.radio_stations";

# This array will hold each saved station as one line of the form
# "Station Name::Stream URL". Populated below by reading the config file.
my @STATIONS;

# ANSI escape sequences for terminal colors. \e is the literal ESC character.
# These render as colored text in any reasonably modern terminal.
my $CYAN   = "\e[36m";    # Cyan foreground
my $GREEN  = "\e[32m";    # Green foreground
my $YELLOW = "\e[33m";    # Yellow foreground
my $BOLD   = "\e[1m";     # Bold/bright
my $RESET  = "\e[0m";     # Reset all formatting back to normal

# ------------------------------------------------------------------------------
# First-run bootstrap: if the config file doesn't exist, create one with a few
# sensible default stations so the user has something to listen to.
# ------------------------------------------------------------------------------
if (! -f $CONFIG_FILE) {                     # -f is Perl's "file exists and is regular file" test
    print "${YELLOW}Creating default station list at $CONFIG_FILE...${RESET}\n";

    # Open in write mode ('>'). The 'or die' idiom aborts with an error if the
    # open fails. $! is Perl's "last system error message" variable.
    open(my $fh, '>', $CONFIG_FILE) or die "Cannot create $CONFIG_FILE: $!";

    # Heredoc syntax: <<'TAG' starts a multi-line string ending at TAG.
    # Single quotes around the tag mean "do NOT interpolate $variables" -
    # which is what we want here, since these are literal config defaults.
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
# Read the config file line by line, ignoring blank lines and comments (#).
# Each surviving line becomes one entry in @STATIONS.
# ------------------------------------------------------------------------------
open(my $cfg, '<', $CONFIG_FILE) or die "Cannot open $CONFIG_FILE: $!";
while (my $line = <$cfg>) {                  # <$cfg> reads one line including newline
    chomp $line;                             # Strip the trailing newline
    next if $line =~ /^\s*$/;                # Skip lines that are blank/whitespace-only
    next if $line =~ /^\s*#/;                # Skip comment lines (start with optional WS then #)
    push @STATIONS, $line;                   # Append the survivor to our station array
}
close($cfg);

# ==============================================================================
# FUNCTIONS
# ==============================================================================

# ------------------------------------------------------------------------------
# show_help - Print usage info and exit. Mirrors the help text of the original
# zsh script, but uses plain ASCII labels in place of emoji.
# ------------------------------------------------------------------------------
sub show_help {
    # basename($0) gives just the script's filename, dropping any directory path.
    # $0 is the magic variable holding the program name as it was invoked.
    my $name = basename($0);

    # Heredoc with double-quoted tag: <<"END" interpolates $variables inside.
    print <<"END";
${BOLD}Usage:${RESET} $name [OPTIONS] [STATION_NUMBER]

Play and discover internet radio streams directly from the command line.

${BOLD}Options:${RESET}
  -s NUM     Select station by number (e.g., -s 2)
  -l         List all saved stations
  -f QUERY   Find/discover new stations on the web (e.g., -f 'jazz')
  -o         Enable 'Old Time Radio' audio filter (lo-fi AM sound)
  -i         Dump initial station metadata (ffprobe required)
  -h         Show this help message and exit
END
    exit 0;
}

# ------------------------------------------------------------------------------
# list_stations - Print a numbered list of all saved stations. We split each
# entry on '::' and only show the name (the human-readable left half).
# ------------------------------------------------------------------------------
sub list_stations {
    # 0 .. $#STATIONS  is the range of valid array indices ($#arr = last index).
    # Perl arrays are 0-indexed internally, so we display $i + 1 to the user.
    for my $i (0 .. $#STATIONS) {
        # split with a limit of 2 means "split on the FIRST '::' only", so
        # if the URL itself contained '::' it wouldn't be over-split.
        my ($name) = split /::/, $STATIONS[$i], 2;
        printf "  %s%d)%s %s\n", $CYAN, $i + 1, $RESET, $name;
    }
}

# ------------------------------------------------------------------------------
# uri_escape - Tiny percent-encoder for URL query strings. We can't rely on
# URI::Escape (not a core module), so we roll our own. Anything outside the
# RFC 3986 "unreserved" set gets converted to %XX hex form.
# Example: "jazz fusion" -> "jazz%20fusion".
# ------------------------------------------------------------------------------
sub uri_escape {
    my ($str) = @_;                          # Function args arrive in @_ ; unpack the first
    # The substitution: capture any char NOT in the safe set, replace with %XX.
    # The /e flag makes the replacement an expression (sprintf call here).
    # ord() gets the byte value, sprintf "%02X" formats as 2-digit uppercase hex.
    $str =~ s/([^A-Za-z0-9\-._~])/sprintf("%%%02X", ord($1))/ge;
    return $str;
}

# ------------------------------------------------------------------------------
# discover_stations - Query Radio-Browser.info for stations matching a search
# term, show the results, and let the user save one to their config.
# ------------------------------------------------------------------------------
sub discover_stations {
    my ($query) = @_;

    # We need 'curl' for the HTTP request. JSON parsing is now done in pure
    # Perl via JSON::PP, so we no longer need the 'jq' tool the zsh version had.
    # system() returns the child exit status; 0 means success.
    if (system("command -v curl > /dev/null 2>&1") != 0) {
        print STDERR "${YELLOW}Error: Stream discovery requires 'curl' to be installed.${RESET}\n";
        exit 1;
    }

    print "\n${BOLD}${CYAN}>> Searching Radio-Browser.info for: '$query'...${RESET}\n\n";

    # Build the API URL. uri_escape ensures spaces/punctuation in the query
    # don't break the URL. String concatenation in Perl is the . operator.
    my $api_url = 'https://de1.api.radio-browser.info/json/stations/search'
                . '?name=' . uri_escape($query)
                . '&limit=10&hidebroken=true';

    # Backticks run a shell command and capture its stdout into a Perl scalar.
    # -s = silent, -L = follow redirects. Quoting $api_url for the shell.
    my $response = `curl -sL "$api_url"`;

    # Parse JSON inside an eval block so a malformed response can't kill us.
    # If decode_json dies, $@ will hold the error message.
    my $data = eval { decode_json($response) };
    if ($@ || ref($data) ne 'ARRAY') {
        print STDERR "${YELLOW}Error: Could not parse response from Radio-Browser.info.${RESET}\n";
        exit 1;
    }

    # $data is a reference to an array of hashrefs - dereference with @$data.
    my $count = scalar @$data;
    if ($count == 0) {
        print "No active stations found for that query.\n";
        exit 0;
    }

    # Walk the results and pretty-print each one.
    for my $i (0 .. $count - 1) {
        my $s = $data->[$i];                 # arrow syntax dereferences array/hash refs

        # The // operator (defined-or): use the right side if the left is undef.
        # This guards against missing fields in the API response.
        my $name    = $s->{name}    // '(unknown)';
        my $bitrate = $s->{bitrate} // 0;
        my $tags    = $s->{tags}    // '';

        printf "  %s%d)%s %s%s%s (%s kbps)\n",
            $CYAN, $i + 1, $RESET, $BOLD, $name, $RESET, $bitrate;
        if (length $tags) {
            print "     ${YELLOW}Tags:${RESET} $tags\n";
        }
    }

    # Prompt the user to optionally save one of the listed stations.
    print "\nEnter a number to SAVE to your list (or press Enter to exit): ";
    my $choice = <STDIN>;                    # Read one line from standard input
    chomp $choice if defined $choice;        # Trim trailing newline (if user pressed Enter at all)

    # Validate the input: must be all digits and within range.
    # Anything else (empty, letters, out of range) just skips the save.
    if (defined $choice && $choice =~ /^\d+$/ && $choice >= 1 && $choice <= $count) {
        my $picked = $data->[$choice - 1];
        my $name = $picked->{name} // 'Unknown Station';
        my $url  = $picked->{url}  // '';

        # Append the new station to the config file ('>>' = append mode).
        open(my $out, '>>', $CONFIG_FILE) or die "Cannot append to $CONFIG_FILE: $!";
        # Use explicit concatenation rather than "$name::$url" because Perl
        # could mistakenly read $name:: as a package-qualified variable.
        print $out $name . '::' . $url . "\n";
        close($out);

        print "${GREEN}[OK] Saved '$name' to $CONFIG_FILE!${RESET}\n";
    }
    exit 0;
}

# ------------------------------------------------------------------------------
# dump_info - Use ffprobe to peek at a stream's metadata headers (ICY tags,
# ID3 tags, Ogg tags, etc.) before playback starts.
# ------------------------------------------------------------------------------
sub dump_info {
    my ($url) = @_;
    print "\n${BOLD}${CYAN}=== Stream Information ===${RESET}\n";

    # If ffprobe isn't installed, say so and bail out cleanly.
    if (system("command -v ffprobe > /dev/null 2>&1") != 0) {
        print "  ${YELLOW}(Install 'ffprobe' to see deep metadata)${RESET}\n";
        print "${BOLD}${CYAN}==========================${RESET}\n\n";
        return;
    }

    # Ask ffprobe for ALL format tags rather than only the icy-* ones. This
    # catches both Shoutcast-style ICY headers AND standard tags like 'title'
    # or 'service_name' that Ogg/Opus streams tend to use.
    #   -v quiet                          : suppress ffprobe's progress chatter
    #   -show_entries format_tags         : we only want the metadata block
    #   -of default=...                   : flat "key=value" output, with keys
    my $probe = `ffprobe -v quiet -show_entries format_tags -of default=noprint_wrappers=1:nokey=0 "$url" 2>/dev/null`;

    if (!defined $probe || $probe eq '') {
        print "  ${YELLOW}No metadata headers found. The station might not broadcast tags.${RESET}\n";
        print "${BOLD}${CYAN}==========================${RESET}\n\n";
        return;
    }

    # Use a hash as a "set" to deduplicate identical output lines. A station
    # that sends BOTH 'icy-name' and 'service_name' with the same value would
    # otherwise produce two identical printed lines.
    my %seen;

    # Walk each line of ffprobe's output. split with /\n/ breaks the string.
    for my $line (split /\n/, $probe) {

        # Each line looks like 'TAG:key=value' (or sometimes just 'key=value').
        # Capture everything after the FIRST '=' as the tag value.
        next unless $line =~ /=(.*)$/;
        my $value = $1;                      # $1 holds the first regex capture group

        # Skip tags whose value is empty or whitespace-only - some streams
        # advertise the field but leave it blank, which would otherwise
        # produce ugly "Station:" lines with nothing after them.
        next if $value =~ /^\s*$/;

        # Decide which human-readable label this tag deserves. We check the
        # key part of the line with a regex. \b is a word boundary, which
        # prevents 'genre=' from matching inside something like 'subgenre='.
        my $out;
        if    ($line =~ /icy-name=/         || $line =~ /service_name=/) { $out = "  Station: $value"; }
        elsif ($line =~ /icy-genre=/        || $line =~ /\bgenre=/     ) { $out = "  Genre:   $value"; }
        elsif ($line =~ /icy-br=/           || $line =~ /\bbitrate=/   ) { $out = "  Bitrate: $value kbps"; }
        elsif ($line =~ /icy-description=/                             ) { $out = "  Desc:    $value"; }
        elsif ($line =~ /StreamTitle=/      || $line =~ /\btitle=/     ) { $out = "  Track:   $value"; }
        else  { next; }                      # Some other tag we don't care about

        # The post-increment $seen{$out}++ returns 0 the first time we see
        # this exact line, then non-zero forever after. So 'unless' prints once.
        unless ($seen{$out}++) {
            print "$out\n";
        }
    }

    print "${BOLD}${CYAN}==========================${RESET}\n\n";
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

# Variables we'll fill in based on the command line.
my $STATION_CHOICE   = '';                   # Which station number to play
my $FILTER_OLD_RADIO = 0;                    # 1 if user passed -o
my $SHOW_INFO        = 0;                    # 1 if user passed -i

# Getopt::Std layout:
#   's:' and 'f:' have a colon, meaning they REQUIRE a value (e.g. -s 3).
#   'l', 'o', 'i', 'h' have no colon - they are simple boolean flags.
# Parsed results land in the %opts hash; e.g. -o sets $opts{o} to 1.
my %opts;
unless (getopts('s:f:loih', \%opts)) {
    print STDERR "${YELLOW}Invalid option.${RESET}\n";
    show_help();
}

# -h: show help and exit.
show_help() if $opts{h};

# -l: just list stations and exit. No need to load mpv or anything.
if ($opts{l}) {
    list_stations();
    exit 0;
}

# -f QUERY: jump straight into the discovery flow (which exits on its own).
discover_stations($opts{f}) if defined $opts{f};

# -s NUM: pre-set the station choice (we'll still validate before using it).
$STATION_CHOICE = $opts{s} if defined $opts{s};

# -o: enable the lo-fi AM radio audio filter.
$FILTER_OLD_RADIO = 1 if $opts{o};

# -i: dump stream info before playing.
$SHOW_INFO = 1 if $opts{i};

# After getopts processes flags, @ARGV holds any leftover positional args.
# Allows the user to write 'am_radio.pl 3' as shorthand for 'am_radio.pl -s 3'.
if ($STATION_CHOICE eq '' && @ARGV > 0) {
    $STATION_CHOICE = $ARGV[0];
}

# ==============================================================================
# MAIN SCRIPT LOGIC
# ==============================================================================

# 'mpv' is mandatory - it's the actual audio player. Bail if missing.
if (system("command -v mpv > /dev/null 2>&1") != 0) {
    print STDERR "Error: 'mpv' is required but not installed.\n";
    exit 1;
}

# If we still don't have a station selection by this point, prompt for one.
if ($STATION_CHOICE eq '') {
    print "${BOLD}Select a station:${RESET}\n";
    list_stations();
    print "\nEnter station number: ";
    $STATION_CHOICE = <STDIN>;
    chomp $STATION_CHOICE if defined $STATION_CHOICE;
}

# Validate the choice: must be all digits, and within [1, number of stations].
my $n = scalar @STATIONS;
if ($STATION_CHOICE !~ /^\d+$/ || $STATION_CHOICE < 1 || $STATION_CHOICE > $n) {
    print STDERR "${YELLOW}Error: Invalid selection. Please enter a number between 1 and $n.${RESET}\n";
    exit 1;
}

# Split the chosen line on '::' to separate name from URL. Limit of 2 means
# we never split more than once, so a URL with '::' would survive intact.
# Note we subtract 1 because the user enters 1-based, but Perl arrays are 0-based.
my ($STATION_NAME, $STATION_URL) = split /::/, $STATIONS[$STATION_CHOICE - 1], 2;

# ------------------------------------------------------------------------------
# Build the mpv argument list as a Perl array. We'll pass it to system() as
# a list (not a single string) so no shell is involved, which means weird
# characters in URLs can't cause quoting/escaping bugs.
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# IPC / track-polling strategy
# ------------------------------------------------------------------------------
# mpv's --term-status-msg trick with ${media-title} or ${metadata/icy-title}
# turns out to be unreliable for streaming radio: the status line doesn't
# always redraw when the server pushes a new ICY title, so the displayed
# track gets stuck on whatever was playing when mpv first connected.
#
# Solution: use mpv's JSON IPC protocol instead.
#   1. Launch mpv with --input-ipc-server=/tmp/am_radio_<pid>.sock
#      (this makes mpv listen on a Unix-domain socket for commands)
#   2. fork() a child process that connects to that socket every 30 seconds,
#      sends {"command": ["get_property", "metadata/icy-title"]}, and prints
#      the current track if (and only if) it has changed.
#   3. When mpv exits, kill the child and remove the socket file.
#
# The IPC socket path is unique per run thanks to $$ (the script's PID),
# so multiple instances of this script can run in parallel without clashing.
# ------------------------------------------------------------------------------

my $IPC_SOCKET = "/tmp/am_radio_$$.sock";

my @MPV_ARGS = (
    '--no-video',                            # Audio only - don't open a video window
    '--display-tags=',                       # Suppress mpv's own tag spam
    '--msg-level=all=error',                 # Quiet unless something actually breaks
    "--input-ipc-server=$IPC_SOCKET",        # Open the IPC socket our poller will talk to
    # NOTE: we deliberately do NOT set --term-status-msg here. mpv's status
    # line doesn't reliably refresh on ICY metadata updates, so instead the
    # polling child below is responsible for printing "Now Playing" lines.
);

# If -o was given, append an ffmpeg audio-filter chain that fakes an old
# AM radio sound:
#   highpass=f=300   - drops bass frequencies below 300 Hz
#   lowpass=f=4500   - drops treble frequencies above 4500 Hz
#   acompressor      - squashes dynamic range, like an AM transmitter would
# Combined, the result is that classic tinny vintage AM-radio timbre.
if ($FILTER_OLD_RADIO) {
    print "${YELLOW}[!] Lo-Fi AM Radio filter activated.${RESET}\n";
    push @MPV_ARGS, '--af=lavfi=[highpass=f=300,lowpass=f=4500,acompressor]';
}

# If -i was given, dump metadata before tuning in.
dump_info($STATION_URL) if $SHOW_INFO;

print "\n${BOLD}Tuning in to $STATION_NAME...${RESET}\n";
print "Press ${YELLOW}Ctrl+C${RESET} to stop playback.\n\n";

# ------------------------------------------------------------------------------
# Fork a polling child BEFORE launching mpv.
# ------------------------------------------------------------------------------
# Process layout while playing:
#
#       parent perl  --(blocks in system)-->  mpv  (audio playback)
#            |
#            +--(fork)--> child perl --(every 30s)--> IPC socket --> mpv
#                                       prints "Now Playing: ..."
#
# fork() returns:
#   * undef  on failure
#   * 0      to the CHILD process
#   * the child's PID to the PARENT process
# ------------------------------------------------------------------------------

my $poller_pid = fork();
die "fork() failed: $!" unless defined $poller_pid;

if ($poller_pid == 0) {
    # ============================================================
    # CHILD PROCESS - polls mpv's IPC socket every 30 seconds
    # ============================================================
    poll_track_loop($IPC_SOCKET);
    # _exit (lower-case) skips Perl's END blocks and DESTROY calls.
    # Important here so the child doesn't try to clean up resources
    # the parent still owns (like the socket file).
    POSIX::_exit(0);
}

# ============================================================
# PARENT PROCESS - runs mpv, then cleans up
# ============================================================

# system() with a list (not a string) bypasses the shell entirely.
# This call BLOCKS until mpv exits (Ctrl+C or natural end of stream).
system('mpv', @MPV_ARGS, $STATION_URL);

# mpv has exited - shut down the polling child and remove the socket.
# kill 'TERM' sends SIGTERM (signal 15) to the child by PID.
# waitpid reaps it so it doesn't linger as a zombie process.
kill 'TERM', $poller_pid;
waitpid($poller_pid, 0);

# Remove the leftover socket file. -e checks "does this path exist".
unlink $IPC_SOCKET if -e $IPC_SOCKET;

exit 0;

# ==============================================================================
# IPC POLLING SUBROUTINES (used only by the forked child)
# ==============================================================================

# ------------------------------------------------------------------------------
# poll_track_loop - The child's main loop. Waits for mpv's socket to appear,
# then queries the current ICY title every 30 seconds and prints it whenever
# it changes.
# ------------------------------------------------------------------------------
sub poll_track_loop {
    my ($socket_path) = @_;

    # mpv takes a moment to set up its IPC socket after launch. Poll for the
    # socket file's existence for up to 15 seconds before giving up.
    # The -S file test is "exists and is a socket".
    my $waited = 0;
    while (! -S $socket_path) {
        return if $waited >= 15;             # mpv apparently never started
        sleep 1;
        $waited++;
    }

    # Give mpv a couple more seconds to actually connect to the stream and
    # receive the first ICY metadata burst before we ask for it.
    sleep 2;

    my $last_title;                          # Remembers the last title we printed
    my $req_id    = 0;                       # Unique ID per IPC request

    # Infinite loop - the parent will SIGTERM us when mpv exits.
    while (1) {
        $req_id++;
        my $title = ipc_get_property($socket_path, 'metadata/icy-title', $req_id);

        # Only act when the title is non-empty AND has actually changed.
        # Stations that don't broadcast ICY titles (talk radio, news) will
        # return undef forever - we just stay quiet in that case.
        if (defined $title && length $title) {
            if (!defined $last_title || $title ne $last_title) {

                # Track changed (or this is the first time we've seen it).
                # Pull the surrounding metadata so we can render the same
                # "=== Stream Information ===" block dump_info() uses, but
                # with the FRESH track title baked in.
                #
                # Each ipc_get_property call gets a unique request_id so
                # mpv's reply can't be confused with another query's reply.
                $req_id++;
                my $station = ipc_get_property($socket_path, 'metadata/icy-name',  $req_id);
                $req_id++;
                my $genre   = ipc_get_property($socket_path, 'metadata/icy-genre', $req_id);
                $req_id++;
                my $bitrate = ipc_get_property($socket_path, 'metadata/icy-br',    $req_id);

                # Helper to test if an IPC value is worth printing - some
                # stations advertise empty fields (e.g. icy-name="").
                # The defined-and-nonblank check keeps the block tidy.
                my $has = sub {
                    my ($v) = @_;
                    return defined $v && $v =~ /\S/;     # has at least one non-space char
                };

                # Print the block. The leading \n is a "fresh line" cushion
                # so we don't collide with anything mpv may have printed.
                print "\n${BOLD}${CYAN}=== Now Playing ===${RESET}\n";
                print "  Track:   $title\n";
                print "${BOLD}${CYAN}==========================${RESET}\n";

                $last_title = $title;
            }
        }

        sleep 30;                            # Wait half a minute, then poll again
    }
}

# ------------------------------------------------------------------------------
# ipc_get_property - Send one "get_property" command over mpv's JSON IPC and
# return the value (or undef on any failure).
#
# The IPC protocol is line-based JSON over a Unix socket:
#   We send:  {"command":["get_property","NAME"],"request_id":N}\n
#   We get:   {"data":VALUE,"error":"success","request_id":N}\n
#
# But mpv ALSO pushes asynchronous event messages on the same socket
# (e.g. property-change notifications), so we have to skim past those
# until we find the reply that matches our request_id.
# ------------------------------------------------------------------------------
sub ipc_get_property {
    my ($socket_path, $property, $id) = @_;

    # Open a fresh connection to the socket. SOCK_STREAM = TCP-like reliable
    # ordered byte stream (the standard choice for Unix sockets).
    my $sock = IO::Socket::UNIX->new(
        Type => SOCK_STREAM,
        Peer => $socket_path,
    );
    return undef unless $sock;               # mpv may have already exited

    # Build and send the JSON command. Note the trailing \n: mpv's IPC
    # parser is line-oriented, so the newline tells it "command complete".
    my $request = encode_json({
        command    => [ 'get_property', $property ],
        request_id => $id,
    });
    print $sock "$request\n";

    my $value;
    # Read replies line by line until we find the one matching our request_id.
    # Some of the lines will be unrelated event notifications - skip those.
    while (my $line = <$sock>) {
        chomp $line;
        next unless length $line;            # Defensive: ignore blanks

        # eval { } catches any decode_json exception (malformed JSON would
        # otherwise kill the child). $@ holds the error if it dies.
        my $msg = eval { decode_json($line) };
        next if $@;                          # Bad JSON - just skip
        next unless ref($msg) eq 'HASH';     # Should always be a JSON object

        # Match on request_id so we ignore mpv's spontaneous event messages.
        if (defined $msg->{request_id} && $msg->{request_id} == $id) {
            # error == "success" means the property was readable; anything
            # else (e.g. "property unavailable") means there's no track info.
            if (defined $msg->{error} && $msg->{error} eq 'success') {
                $value = $msg->{data};
            }
            last;                            # We got our reply - stop reading
        }
    }
    close $sock;

    return $value;
}

