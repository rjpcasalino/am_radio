package AmRadio::IPC;

# ==============================================================================
# AmRadio::IPC - mpv JSON IPC socket utilities
#
# Handles:
#   * ipc_get_property()  - send a get_property command, return the value
#   * poll_track_loop()   - background ICY-title watcher for non-TUI playback
# ==============================================================================

use strict;
use warnings;
use Exporter 'import';
use IO::Socket::UNIX;
use IO::Select;
use JSON::PP qw(encode_json decode_json);
use Time::HiRes qw(time sleep);
use AmRadio::Colors qw(:all);

our @EXPORT_OK = qw( ipc_get_property poll_track_loop );

# ------------------------------------------------------------------------------
# ipc_get_property - send a JSON 'get_property' command and return the value.
# Bounded by $timeout seconds so a frozen mpv can't hang the caller.
# ------------------------------------------------------------------------------
sub ipc_get_property {
    my ($socket_path, $property, $id, $timeout) = @_;
    $timeout //= 0.5;

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
    syswrite($sock, "$request\n");

    my $sel      = IO::Select->new($sock);
    my $buf      = '';
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
                return $value;
            }
        }
    }

    close $sock;
    return $value;
}

# ------------------------------------------------------------------------------
# poll_track_loop - background ICY-title watcher for non-TUI playback.
# Waits for mpv's socket, then polls every 5 s and prints "Now Playing" on
# track change.
# ------------------------------------------------------------------------------
sub poll_track_loop {
    my ($socket_path) = @_;

    my $waited = 0;
    while (! -S $socket_path) {
        return if $waited >= 15;
        sleep 1;
        $waited++;
    }
    sleep 2;    # let mpv connect to the stream

    my $last_title;
    my $req_id = 0;
    my $has    = sub { defined $_[0] && $_[0] =~ /\S/ };

    while (1) {
        $req_id++;
        my $title = ipc_get_property($socket_path, 'metadata/icy-title', $req_id);

        if (defined $title && length $title) {
            if (!defined $last_title || $title ne $last_title) {
                $req_id++; my $station = ipc_get_property($socket_path, 'metadata/icy-name',  $req_id);
                $req_id++; my $genre   = ipc_get_property($socket_path, 'metadata/icy-genre', $req_id);
                $req_id++; my $bitrate = ipc_get_property($socket_path, 'metadata/icy-br',    $req_id);

                print "\n${BOLD}${CYAN}=== Now Playing ===${RESET}\n";
                print "  Station: $station\n"      if $has->($station);
                print "  Genre:   $genre\n"        if $has->($genre);
                print "  Bitrate: $bitrate kbps\n" if $has->($bitrate);
                print "  Track:   $title\n";
                print "${BOLD}${CYAN}==========================${RESET}\n";

                $last_title = $title;
            }
        }

        sleep 5;
    }
}

1;
