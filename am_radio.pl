#!/usr/bin/env perl

# ==============================================================================
# am_radio.pl - A command-line internet radio player (with optional TUI mode)
# ------------------------------------------------------------------------------
# This is the main entry point.  All functionality lives in lib/AmRadio/*.pm:
#
#   AmRadio::Colors     - ANSI color constants
#   AmRadio::Config     - station list management
#   AmRadio::Discovery  - Radio-Browser.info search + stream metadata
#   AmRadio::IPC        - mpv JSON IPC socket utilities
#   AmRadio::TUI        - vintage tube-radio terminal UI driver
#
# External programs required at runtime:
#   mpv      - to play audio (mandatory)
#   curl     - only for -f (find/discover) feature
#   ffprobe  - only for -i (info) feature
# ==============================================================================

use strict;
use warnings;
use utf8;
use File::Basename qw(basename);
use Getopt::Long   qw(:config no_ignore_case bundling);
use POSIX          ();

use lib 'lib';
use AmRadio::Colors    qw(:all);
use AmRadio::Config    qw(load_stations list_stations load_afn_stations @STATIONS);
use AmRadio::Discovery qw(discover_stations dump_info);
use AmRadio::IPC       qw(poll_track_loop);
use AmRadio::TUI       qw(radio_tui);

binmode STDOUT, ':encoding(UTF-8)';
binmode STDERR, ':encoding(UTF-8)';

# ==============================================================================
# Help
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

${BOLD}Long options (use with -t):${RESET}
  --resize   Ask the terminal emulator to resize to the TUI panel
             dimensions (67x22) on launch and restore on exit.

${BOLD}Special station presets:${RESET}
  --afn      Load American Forces Network (AFN) stations

${BOLD}Discovery examples:${RESET}
  $name -f                     # Interactive menu
  $name -f 'jazz'              # Quick search for 'jazz' stations
  $name -f 'BBC'               # Quick search for BBC stations

${BOLD}AFN examples:${RESET}
  $name --afn -l               # List all AFN stations
  $name --afn -t               # Launch TUI with AFN stations
  $name --afn -s 1             # Play first AFN station

${BOLD}Tuner mode keys:${RESET}
  ${CYAN}<- ->${RESET}        Tune to previous / next station
  ${CYAN}1${RESET}-${CYAN}9${RESET}          Jump to preset (first 9 stations)
  ${CYAN}o${RESET}            Toggle Lo-Fi AM filter
  ${CYAN}i${RESET}            Show verbose stream info (press any key to return)
  ${CYAN}r${RESET}            Re-tune (kick mpv if a stream stalls)
  ${CYAN}f${RESET}            Search for stations (music keeps playing)
  ${CYAN}q${RESET} / ${CYAN}Esc${RESET}      Quit
END
    exit 0;
}

# ==============================================================================
# Argument parsing
# ==============================================================================

my ($opt_station, $opt_find, $opt_list, $opt_old_radio,
    $opt_info, $opt_tui, $opt_verbose, $opt_help,
    $opt_resize, $opt_afn);

GetOptions(
    's=i'    => \$opt_station,
    'f:s'    => \$opt_find,
    'l'      => \$opt_list,
    'o'      => \$opt_old_radio,
    'i'      => \$opt_info,
    't'      => \$opt_tui,
    'v'      => \$opt_verbose,
    'h'      => \$opt_help,
    'resize' => \$opt_resize,
    'afn'    => \$opt_afn,
) or do {
    print STDERR "${YELLOW}Invalid option. Try -h for help.${RESET}\n";
    exit 1;
};

show_help() if $opt_help;

# ==============================================================================
# Station loading
# ==============================================================================

if ($opt_afn) {
    load_afn_stations();
} else {
    load_stations();
}

# Positional argument can override -s
$opt_station //= $ARGV[0] if @ARGV;

# ==============================================================================
# Simple flag actions (no playback)
# ==============================================================================

if ($opt_list) {
    list_stations();
    exit 0;
}

if (defined $opt_find) {
    # -f with no value gives '' (empty string); treat same as undef (interactive)
    discover_stations(length($opt_find) ? $opt_find : undef);
    exit 0;
}

# ==============================================================================
# Forward flags into modules
# ==============================================================================

$AmRadio::TUI::VERBOSE  = $opt_verbose ? 1 : 0;
$AmRadio::TUI::RESIZE_TERM = $opt_resize ? 1 : 0;

# Shared verbose logger used by classic (non-TUI) flow
my $VERBOSE = $opt_verbose ? 1 : 0;
sub verbose_log {
    return unless $VERBOSE;
    my ($msg) = @_;
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime(time);
    printf STDERR "${DIM}[%04d-%02d-%02d %02d:%02d:%02d] [am_radio] %s${RESET}\n",
                  $year+1900, $mon+1, $mday, $hour, $min, $sec, $msg;
}

# ==============================================================================
# Require mpv
# ==============================================================================

if (system("command -v mpv > /dev/null 2>&1") != 0) {
    print STDERR "Error: 'mpv' is required but not installed.\n";
    exit 1;
}

# ==============================================================================
# TUI mode
# ==============================================================================

if ($opt_tui) {
    my $start_idx = 0;
    if (defined $opt_station) {
        my $n = scalar @STATIONS;
        unless ($opt_station =~ /^\d+$/ && $opt_station >= 1 && $opt_station <= $n) {
            print STDERR "${YELLOW}Invalid station number for -s.${RESET}\n";
            exit 1;
        }
        $start_idx = $opt_station - 1;
    }
    radio_tui($start_idx, $opt_old_radio ? 1 : 0);
    exit 0;
}

# ==============================================================================
# Classic flow: prompt → mpv + polling child
# ==============================================================================

my $station_choice = $opt_station;

unless (defined $station_choice) {
    print "${BOLD}Select a station:${RESET}\n";
    list_stations();
    print "\nEnter station number: ";
    $station_choice = <STDIN>;
    chomp $station_choice if defined $station_choice;
}

my $n = scalar @STATIONS;
unless (defined $station_choice && $station_choice =~ /^\d+$/
        && $station_choice >= 1 && $station_choice <= $n) {
    print STDERR "${YELLOW}Error: Invalid selection. Please enter a number between 1 and $n.${RESET}\n";
    exit 1;
}

my ($STATION_NAME, $STATION_URL) = split /::/, $STATIONS[$station_choice - 1], 2;

my $IPC_SOCKET = "/tmp/am_radio_$$.sock";
unlink $IPC_SOCKET if -e $IPC_SOCKET;
END { unlink $IPC_SOCKET if defined $IPC_SOCKET && -e $IPC_SOCKET }

my @MPV_ARGS = (
    '--no-video',
    '--display-tags=',
    '--msg-level=all=error',
    "--input-ipc-server=$IPC_SOCKET",
);

if ($opt_old_radio) {
    print "${YELLOW}[!] Lo-Fi AM Radio filter activated.${RESET}\n";
    push @MPV_ARGS, '--af=lavfi=[highpass=f=300,lowpass=f=4500,acompressor]';
}

dump_info($STATION_URL) if $opt_info;

verbose_log("Starting playback for: $STATION_NAME");
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
