package AmRadio::TUI;

# ==============================================================================
# AmRadio::TUI - vintage tube-radio terminal UI
#
# Layout (66 cols x 22 rows, Unicode box drawing):
#
#   ╔════════════════════════════════════════════════════════════════╗
#   ║                          AM_RADIO                 [Lo-Fi:OFF] ║
#   ╠════════════════════════════════════════════════════════════════╣
#   ║                                                                ║
#   ║   ┌──────────────────────────────────────────────────────────┐ ║
#   ║   │ ► KEXP Seattle                                  920 kHz  │ ║
#   ║   │ ♪  The Beatles — Here Comes the Sun                      │ ║
#   ║   └──────────────────────────────────────────────────────────┘ ║
#   ║                                                                ║
#   ║   FREQUENCY                                                    ║
#   ║                       ▼                                        ║
#   ║   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━   ║
#   ║   ╎    ╎    ╎    │    ╎    ╎    ╎    ╎    ╎    ╎    ╎    ╎    ║
#   ║   540   700  900  1080 1260 1440  1620 1700               kHz  ║
#   ║                                                                ║
#   ║                         PRESETS  1 2 3 4 5 6 7 8 9            ║
#   ║                                                                ║
#   ║   > Tuning…                                                    ║
#   ╠════════════════════════════════════════════════════════════════╣
#   ║  ◀ ▶ tune   1-9 preset   o lo-fi   r retune   f find   q quit ║
#   ╚════════════════════════════════════════════════════════════════╝
#
# Public entry point: radio_tui($initial_idx, $initial_filter)
# ==============================================================================

use strict;
use warnings;
use utf8;
use Exporter 'import';
use POSIX qw(:termios_h :sys_wait_h);
use Time::HiRes qw(time sleep);
use JSON::PP     qw(decode_json);
use AmRadio::Colors     qw(:all);
use AmRadio::IPC        qw(ipc_get_property);
use AmRadio::Discovery  qw(run_capture uri_escape tool_on_path);
use AmRadio::Config     qw(save_station $CONFIG_FILE @STATIONS);

our @EXPORT_OK = qw( radio_tui );

# Panel geometry constants — don't change without re-checking row math.
use constant {
    TUI_WIDTH      => 66,
    TUI_INNER      => 64,
    TUI_HEIGHT     => 22,
    TUI_DIAL_WIDTH => 56,
    TUI_DIAL_LEFT  => 4,
};

# Set by main script; controls whether we ask the terminal to resize.
our $RESIZE_TERM = 0;

# Verbose flag forwarded from main script.
our $VERBOSE = 0;

# ==============================================================================
# Terminal helpers
# ==============================================================================

sub tui_term_setup {
    my $saved = POSIX::Termios->new;
    $saved->getattr(fileno(STDIN));

    my $tio = POSIX::Termios->new;
    $tio->getattr(fileno(STDIN));
    $tio->setlflag($tio->getlflag & ~(ECHO | ICANON));
    $tio->setcc(VMIN,  0);
    $tio->setcc(VTIME, 0);
    $tio->setattr(fileno(STDIN), TCSANOW);
    return $saved;
}

sub tui_term_restore {
    my ($saved) = @_;
    $saved->setattr(fileno(STDIN), TCSANOW) if $saved;
}

sub tui_read_key {
    my ($timeout) = @_;
    my $rin = '';
    vec($rin, fileno(STDIN), 1) = 1;
    my $ready = select($rin, undef, undef, $timeout);
    return undef unless $ready;

    my $buf = '';
    my $n   = sysread(STDIN, $buf, 8);
    return undef if !defined $n || $n == 0;

    return 'left'  if $buf eq "\e[D";
    return 'right' if $buf eq "\e[C";
    return 'up'    if $buf eq "\e[A";
    return 'down'  if $buf eq "\e[B";
    return 'esc'   if $buf eq "\e";
    return $buf;
}

sub tui_term_size {
    my $size = `stty size 2>/dev/null`;
    return (24, 80) unless defined $size && length $size;
    chomp $size;
    my ($rows, $cols) = split /\s+/, $size;
    return ($rows || 24, $cols || 80);
}

sub tui_request_term_resize {
    my ($rows, $cols) = @_;
    local $| = 1;
    printf STDOUT "\e[8;%d;%dt", $rows, $cols;
}

# ==============================================================================
# mpv lifecycle helpers
# ==============================================================================

sub _verbose { print STDERR "${DIM}[am_radio] $_[0]${RESET}\n" if $VERBOSE }

sub tui_start_mpv {
    my ($st) = @_;
    my ($name, $url) = split /::/, $st->{stations}[$st->{current}], 2;
    _verbose("TUI: Starting mpv for '$name'");
    unlink $st->{sock} if -e $st->{sock};

    my $pid = fork();
    die "fork failed: $!" unless defined $pid;

    if ($pid == 0) {
        open(STDIN,  '<', '/dev/null');
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null') unless $VERBOSE;
        my @args = (
            'mpv', '--no-video', '--no-terminal',
            '--display-tags=', '--msg-level=all=error',
            "--input-ipc-server=$st->{sock}",
        );
        push @args, '--af=lavfi=[highpass=f=300,lowpass=f=4500,acompressor]' if $st->{filter};
        push @args, $url;
        exec(@args) or POSIX::_exit(127);
    }

    $st->{mpv_pid}    = $pid;
    $st->{track}      = '';
    $st->{last_poll}  = 0;
    $st->{tune_start} = time();
    _verbose("TUI: mpv PID $pid");
}

sub tui_stop_mpv {
    my ($st) = @_;
    my $pid = $st->{mpv_pid};
    return unless $pid;
    _verbose("TUI: Stopping mpv PID $pid");
    kill 'TERM', $pid;
    for (1 .. 20) {
        my $r = waitpid($pid, WNOHANG);
        if ($r == $pid || $r == -1) {
            $st->{mpv_pid} = undef;
            unlink $st->{sock} if -e $st->{sock};
            return;
        }
        sleep 0.05;
    }
    kill 'KILL', $pid;
    waitpid($pid, 0);
    $st->{mpv_pid} = undef;
    unlink $st->{sock} if -e $st->{sock};
}

sub tui_query_track {
    my ($st) = @_;
    return undef unless -S $st->{sock};
    return ipc_get_property($st->{sock}, 'metadata/icy-title', $st->{req_id}++, 0.3);
}

# ==============================================================================
# Station-change actions
# ==============================================================================

sub _set_msg {
    my ($st, $msg, $secs) = @_;
    $st->{msg}       = $msg;
    $st->{msg_until} = time() + ($secs // 1.2);
}

sub tui_change {
    my ($st, $delta) = @_;
    my $n = scalar @{ $st->{stations} };
    return if $n == 0;
    $st->{current} = ($st->{current} + $delta) % $n;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    _set_msg($st, 'Tuning…');
}

sub tui_jump {
    my ($st, $idx) = @_;
    return if $idx < 0 || $idx >= scalar @{ $st->{stations} };
    return if $idx == $st->{current};
    $st->{current} = $idx;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    _set_msg($st, 'Tuning…');
}

sub tui_toggle_filter {
    my ($st) = @_;
    $st->{filter} = $st->{filter} ? 0 : 1;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    _set_msg($st, $st->{filter} ? 'Lo-Fi filter ON' : 'Lo-Fi filter OFF', 1.5);
}

sub tui_retune {
    my ($st) = @_;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    _set_msg($st, 'Re-tuning…');
}

# ==============================================================================
# Stream-info overlay (press 'i' in TUI)
# ==============================================================================

sub tui_dump_stream_info {
    my ($st) = @_;
    my ($name, $url) = split /::/, $st->{stations}[$st->{current}], 2;

    print "\e[2J\e[H";
    print "${BOLD}${CYAN}" . "=" x 70 . "\nStream Information\n" . "=" x 70 . "\n${RESET}\n";
    print "${BOLD}Station Name:${RESET} $name\n";
    print "${BOLD}Stream URL:${RESET}   $url\n";
    print "${BOLD}Current Track:${RESET} " . ($st->{track} || '(no track info)') . "\n\n";

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
        print "  ${DIM}(No ICY metadata available)${RESET}\n" unless $has_metadata;
        print "\n";
    }

    if (_tool_on_path('ffprobe')) {
        print "${CYAN}--- Deep Stream Analysis (ffprobe) ---${RESET}\n";
        my $probe = run_capture(
            'ffprobe', '-v', 'quiet', '-timeout', '5000000',
            '-show_entries', 'format:format_tags:stream',
            '-of', 'default=noprint_wrappers=1', $url,
        );
        if (defined $probe && length $probe) {
            for my $line (split /\n/, $probe) {
                if    ($line =~ /^\[(\w+)\]/)    { print "${GREEN}[$1]${RESET}\n" }
                elsif ($line =~ /^TAG:(.+)=(.+)$/) { printf "  ${DIM}%-20s${RESET} %s\n", "$1:", $2 }
                elsif ($line =~ /^(\w+)=(.+)$/)  { printf "  ${DIM}%-20s${RESET} %s\n", "$1:", $2 }
            }
        } else {
            print "  ${DIM}(No additional metadata available)${RESET}\n";
        }
        print "\n";
    }

    print "${BOLD}${CYAN}" . "=" x 70 . "\n${RESET}";
    print "${YELLOW}Press any key to return to radio...${RESET}\n";

    my $saved_term = tui_term_setup();
    tui_read_key(undef);
    tui_term_restore($saved_term);
    print "\e[2J\e[H";
}

# ==============================================================================
# Drawing primitives
# ==============================================================================

sub _pad_to {
    my ($s, $w) = @_;
    my $l = length $s;
    return $l < $w ? $s . (' ' x ($w - $l)) : substr($s, 0, $w);
}

sub _truncate_to {
    my ($s, $w) = @_;
    return $s if length($s) <= $w;
    return substr($s, 0, $w - 1) . "\x{2026}";    # …
}

sub _centered {
    my ($s, $w) = @_;
    my $extra = $w - length($s);
    return $s if $extra <= 0;
    my $left = int($extra / 2);
    return (' ' x $left) . $s . (' ' x ($extra - $left));
}

sub _fake_freq {
    my ($idx, $total) = @_;
    return 1020 if $total <= 1;
    my $f = 540 + int($idx * (1700 - 540) / ($total - 1) + 0.5);
    return int(($f + 5) / 10) * 10;
}

# ------------------------------------------------------------------------------
# Individual row builders — each returns a TUI_INNER-wide string (with ANSI)
# ------------------------------------------------------------------------------

sub tui_title_row {
    my ($st) = @_;
    my $filter = $st->{filter} ? '[Lo-Fi:ON ]' : '[Lo-Fi:OFF]';
    my $body   = ' ' . _centered('AM_RADIO', 51) . $filter . ' ';
    die "title row width" if length($body) != TUI_INNER;
    my $c = $body;
    $c =~ s/AM_RADIO/${BOLD}${YELLOW}AM_RADIO$RESET/;
    if ($st->{filter}) { $c =~ s/\Q[Lo-Fi:ON ]/$MAGENTA${BOLD}[Lo-Fi:ON ]$RESET/ }
    else               { $c =~ s/\Q[Lo-Fi:OFF]/${DIM}[Lo-Fi:OFF]$RESET/          }
    return $c;
}

sub tui_info_row1 {
    my ($st) = @_;
    my ($name) = split /::/, $st->{stations}[$st->{current}], 2;
    my $freq_label = sprintf '%4d kHz', _fake_freq($st->{current}, scalar @{ $st->{stations} });
    my $inner_card = 58;
    my $name_w     = $inner_card - 2 - 8 - 1;
    my $left       = "\x{25ba} " . _truncate_to($name, $name_w);    # ►
    my $pad        = $inner_card - length($left) - length($freq_label);
    $pad = 1 if $pad < 1;
    my $card_inner = _pad_to($left . (' ' x $pad) . $freq_label, $inner_card);
    my $body = '   │' . $card_inner . '│ ';
    die "info1 width" if length($body) != TUI_INNER;
    my $c = $body;
    $c =~ s/\x{25ba}/${GREEN}${BOLD}\x{25ba}$RESET/;
    $c =~ s/\Q$freq_label/$YELLOW$freq_label$RESET/;
    $c =~ s/│/${CYAN}│$RESET/g;
    return $c;
}

sub tui_info_row2 {
    my ($st) = @_;
    my $track   = $st->{track};
    my $display;
    if (defined $track && length $track) {
        $display = "\x{266a} " . _truncate_to($track, 54);          # ♪
    } else {
        my $w = ($st->{tune_start} && time() - $st->{tune_start} < 5)
            ? '… tuning in …' : '(no track info)';
        $display = "\x{266a} $w";
    }
    my $card_inner = _pad_to($display, 58);
    my $body       = '   │' . $card_inner . '│ ';
    die "info2 width" if length($body) != TUI_INNER;
    my $c = $body;
    $c =~ s/\x{266a}/${GREEN}\x{266a}$RESET/;
    $c =~ s/\(no track info\)/${DIM}(no track info)$RESET/;
    $c =~ s/… tuning in …/${YELLOW}… tuning in …$RESET/;
    $c =~ s/│/${CYAN}│$RESET/g;
    return $c;
}

sub tui_card_top { return "${CYAN}   \x{250c}" . ("\x{2500}" x 58) . "\x{2510} ${RESET}" }
sub tui_card_bot { return "${CYAN}   \x{2514}" . ("\x{2500}" x 58) . "\x{2518} ${RESET}" }

sub tui_dial_needle_row {
    my ($st) = @_;
    my $n   = scalar @{ $st->{stations} };
    my $cur = $st->{current};
    my $pos = $n <= 1 ? int(TUI_DIAL_WIDTH / 2)
                      : int($cur * (TUI_DIAL_WIDTH - 1) / ($n - 1) + 0.5);
    my $body = (' ' x (TUI_DIAL_LEFT + $pos))
             . "\x{25bc}"                                     # ▼
             . (' ' x (TUI_INNER - TUI_DIAL_LEFT - $pos - 1));
    die "needle row width" if length($body) != TUI_INNER;
    (my $c = $body) =~ s/\x{25bc}/${YELLOW}${BOLD}\x{25bc}$RESET/;
    return $c;
}

sub tui_dial_line_row {
    my $body = (' ' x TUI_DIAL_LEFT)
             . ("\x{2501}" x TUI_DIAL_WIDTH)                  # ━
             . (' ' x (TUI_INNER - TUI_DIAL_LEFT - TUI_DIAL_WIDTH));
    die "dial line width" if length($body) != TUI_INNER;
    (my $c = $body) =~ s/(\x{2501}+)/$CYAN$1$RESET/;
    return $c;
}

sub tui_dial_tick_row {
    my ($st) = @_;
    my $n   = scalar @{ $st->{stations} };
    my $cur = $st->{current};
    my @slots = (' ') x TUI_DIAL_WIDTH;

    for my $i (0 .. $n - 1) {
        next if $i == $cur;
        my $p = $n <= 1 ? int(TUI_DIAL_WIDTH / 2)
                        : int($i * (TUI_DIAL_WIDTH - 1) / ($n - 1) + 0.5);
        $p = 0 if $p < 0; $p = TUI_DIAL_WIDTH - 1 if $p > TUI_DIAL_WIDTH - 1;
        $slots[$p] = "${DIM}${CYAN}\x{254e}${RESET}";         # ╎
    }
    my $p_cur = $n <= 1 ? int(TUI_DIAL_WIDTH / 2)
                        : int($cur * (TUI_DIAL_WIDTH - 1) / ($n - 1) + 0.5);
    $p_cur = 0 if $p_cur < 0; $p_cur = TUI_DIAL_WIDTH - 1 if $p_cur > TUI_DIAL_WIDTH - 1;
    $slots[$p_cur] = "${YELLOW}${BOLD}\x{2502}${RESET}";      # │

    return (' ' x TUI_DIAL_LEFT) . join('', @slots)
         . (' ' x (TUI_INNER - TUI_DIAL_LEFT - TUI_DIAL_WIDTH));
}

sub tui_dial_label_row {
    my @labels = (
        [0,  '540'],  [8,  '700'],  [18, '900'],
        [26, '1080'], [33, '1260'], [40, '1440'],
        [47, '1620'], [51, '1700'],
    );
    my @slots = (' ') x TUI_DIAL_WIDTH;
    for my $entry (@labels) {
        my ($pos, $lab) = @$entry;
        for my $ci (0 .. length($lab) - 1) {
            my $p = $pos + $ci;
            $slots[$p] = substr($lab, $ci, 1) if $p < TUI_DIAL_WIDTH;
        }
    }
    my $body = (' ' x TUI_DIAL_LEFT) . join('', @slots)
             . (' ' x (TUI_INNER - TUI_DIAL_LEFT - TUI_DIAL_WIDTH));
    die "label row width" if length($body) != TUI_INNER;
    substr($body, TUI_INNER - 5, 4) = ' kHz';
    (my $c = $body) =~ s/(\d+)/$DIM$1$RESET/g;
    $c =~ s/kHz/${DIM}${CYAN}kHz$RESET/;
    return $c;
}

sub tui_status_row {
    my ($st) = @_;
    my $n          = scalar @{ $st->{stations} };
    my $max_preset = $n > 9 ? 9 : $n;
    my @cells;
    for my $i (1 .. $max_preset) {
        push @cells, ($i - 1 == $st->{current}) ? "[$i]" : " $i ";
    }
    my $body = _pad_to(_centered("PRESETS  " . join('', @cells), TUI_INNER), TUI_INNER);
    (my $c = $body) =~ s/PRESETS/${BOLD}PRESETS$RESET/;
    $c =~ s/\[(\d)\]/${YELLOW}${BOLD}[$1]$RESET/g;
    return $c;
}

sub tui_msg_row {
    my ($st) = @_;
    my $msg = '';
    $msg = '> ' . $st->{msg} if $st->{msg} && time() < $st->{msg_until};
    my $body = _pad_to('   ' . $msg, TUI_INNER);
    (my $c = $body) =~ s/^(\s*> )/${YELLOW}$1$RESET/;
    return $c;
}

sub tui_help_row {
    my $body = '  ◀ ▶ tune   1-9 preset   o lo-fi   i info   r retune   f find   q quit  ';
    $body = _pad_to($body, TUI_INNER);
    (my $c = $body) =~ s/(◀ ▶|1-9|o|i|r|f|q)/${CYAN}$1$RESET/g;
    return $c;
}

sub tui_blank_row { return ' ' x TUI_INNER }

sub tui_search_help_row {
    my ($mode) = @_;
    my $body = $mode == 1
        ? '  Enter=search    1-9 tune & save    Esc=cancel'
        : '  1-9 tune & save    Esc=cancel';
    $body = _pad_to($body, TUI_INNER);
    (my $c = $body) =~ s/(Enter|1-9|Esc)/${CYAN}$1$RESET/g;
    return $c;
}

sub tui_search_content_rows {
    my ($st) = @_;
    my $mode    = $st->{search_mode};
    my $query   = $st->{search_query}  // '';
    my @results = @{ $st->{search_results} // [] };
    my $page    = $st->{search_page}   // 0;

    # Search prompt card
    my $inner_card = 58;
    my $label      = 'Search: ';
    my $max_q_w    = $inner_card - length($label) - 1;
    my $q_display  = _truncate_to($query, $max_q_w);
    my $cursor     = $mode == 1 ? '_' : ' ';
    my $prompt_inner = _pad_to($label . $q_display . $cursor, $inner_card);
    (my $prompt_colored = $prompt_inner) =~ s/Search:/${CYAN}Search:$RESET/;
    $prompt_colored =~ s/_$/${BOLD}_$RESET/ if $mode == 1;
    my $card_row = '   ' . "${CYAN}│$RESET" . $prompt_colored . "${CYAN}│$RESET" . ' ';

    # Status line
    my $status_text;
    if ($mode == 1) {
        $status_text = length($query)
            ? "   Press Enter to search for \"$query\""
            : '   Type a station name and press Enter to search';
    } else {
        my $n           = scalar @results;
        my $total_pages = $n > 0 ? int(($n - 1) / 5) + 1 : 1;
        my $cur_page    = $page + 1;
        my $start       = $page * 5 + 1;
        my $end         = ($page + 1) * 5; $end = $n if $end > $n;
        if ($n > 0) {
            $status_text = sprintf('   %d results (page %d/%d, showing %d-%d) — press 1-5 to tune',
                                   $n, $cur_page, $total_pages, $start, $end);
            $status_text .= ', n/p for next/prev' if $total_pages > 1;
        } else {
            $status_text = '   No stations found. Try a different query.';
        }
    }
    my $status = _pad_to($status_text, TUI_INNER);
    (my $status_colored = $status) =~ s/(1-\d+|n\/p)/${CYAN}$1$RESET/g;

    # Result rows (5 slots per page)
    my @result_rows;
    my $page_start = $page * 5;
    for my $i (0 .. 4) {
        my $r = $results[$page_start + $i] if $page_start + $i < @results;
        if (defined $r) {
            my $num_str = sprintf '%d) ', $i + 1;
            my $bitrate = $r->{bitrate} ? sprintf('%3d kbps', $r->{bitrate}) : '        ';
            my $prefix  = '   ' . $num_str;
            my $suffix  = '  ' . $bitrate;
            my $name_w  = TUI_INNER - length($prefix) - length($suffix);
            my $body    = _pad_to($prefix . _pad_to($r->{name} // '', $name_w) . $suffix, TUI_INNER);
            (my $colored = $body) =~ s/^(\s+\d+\) )/${CYAN}$1$RESET/;
            $colored =~ s/(\d+ kbps)/$YELLOW$1$RESET/;
            push @result_rows, $colored;
        } else {
            push @result_rows, tui_blank_row();
        }
    }

    return (
        tui_blank_row(),
        tui_card_top(),
        $card_row,
        tui_card_bot(),
        tui_blank_row(),
        $status_colored,
        @result_rows,
        tui_blank_row(),
        tui_status_row($st),
        tui_blank_row(),
        tui_msg_row($st),
    );
}

sub tui_draw {
    my ($st) = @_;
    my @rows = (
        "${CYAN}╔" . ('═' x TUI_INNER) . "╗${RESET}",
        "${CYAN}║${RESET}" . tui_title_row($st)      . "${CYAN}║${RESET}",
        "${CYAN}╠" . ('═' x TUI_INNER) . "╣${RESET}",
        "${CYAN}║${RESET}" . tui_blank_row()          . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_card_top()           . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_info_row1($st)       . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_info_row2($st)       . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_card_bot()           . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_blank_row()          . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . _pad_to('   FREQUENCY', TUI_INNER) . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_dial_needle_row($st) . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_dial_line_row()      . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_dial_tick_row($st)   . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_dial_label_row()     . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_blank_row()          . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_status_row($st)      . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_blank_row()          . "${CYAN}║${RESET}",
        "${CYAN}║${RESET}" . tui_msg_row($st)         . "${CYAN}║${RESET}",
        "${CYAN}╠" . ('═' x TUI_INNER) . "╣${RESET}",
        "${CYAN}║${RESET}" . tui_help_row()           . "${CYAN}║${RESET}",
        "${CYAN}╚" . ('═' x TUI_INNER) . "╝${RESET}",
    );

    if ($st->{search_mode}) {
        my @content = tui_search_content_rows($st);
        for my $i (0 .. $#content) {
            $rows[3 + $i] = "${CYAN}║${RESET}" . $content[$i] . "${CYAN}║${RESET}";
        }
        $rows[19] = "${CYAN}║${RESET}" . tui_search_help_row($st->{search_mode}) . "${CYAN}║${RESET}";
    }

    print "\e[H";
    for my $row (@rows) { print $row, "\e[K\n" }
    print "\e[J";
}

# ==============================================================================
# Search actions
# ==============================================================================

sub tui_do_search {
    my ($st) = @_;
    my $query = $st->{search_query} // '';
    return unless length $query;

    $st->{msg}       = 'Searching…';
    $st->{msg_until} = time() + 30;
    tui_draw($st);

    my $url      = 'https://de1.api.radio-browser.info/json/stations/search'
                 . '?name=' . uri_escape($query)
                 . '&limit=50&hidebroken=true&order=votes&reverse=true';
    my $response = run_capture('curl', '-sL', '--max-time', '8', $url);
    my $data     = eval { decode_json($response // '') };

    if ($@ || ref($data) ne 'ARRAY') {
        $st->{search_results} = [];
        $st->{msg}            = 'Search failed — check network connection';
        $st->{msg_until}      = time() + 3;
    } else {
        $st->{search_results} = [ map { {
            name    => $_->{name}    // '',
            url     => $_->{url}     // '',
            bitrate => $_->{bitrate} // 0,
        } } @$data ];
        my $n = scalar @{ $st->{search_results} };
        $st->{msg}       = $n ? "Found $n match(es)" : 'No stations found';
        $st->{msg_until} = time() + 2;
    }
    $st->{search_mode} = 2;
    $st->{search_page} = 0;
}

sub tui_search_select {
    my ($st, $n) = @_;
    my @results = @{ $st->{search_results} // [] };
    my $idx     = ($st->{search_page} // 0) * 5 + $n - 1;
    return if $idx < 0 || $idx >= @results;

    my $r    = $results[$idx];
    my $name = $r->{name} // '';
    my $url  = $r->{url}  // '';
    return unless length $name && length $url;

    $name =~ s/[\r\n]+/ /g;
    $url  =~ s/[\r\n]+//g;

    save_station($name, $url);
    $st->{stations} = \@STATIONS;
    $st->{current}  = $#STATIONS;
    tui_stop_mpv($st);
    tui_start_mpv($st);
    _set_msg($st, 'Tuning to ' . _truncate_to($name, 30), 2);

    $st->{search_mode}    = 0;
    $st->{search_query}   = '';
    $st->{search_results} = [];
}

# ==============================================================================
# Main TUI driver
# ==============================================================================

sub radio_tui {
    my ($initial_idx, $initial_filter) = @_;

    if (@STATIONS == 0) {
        print STDERR "${YELLOW}No stations configured.${RESET}\n";
        return;
    }

    my ($rows, $cols) = tui_term_size();
    my ($orig_rows, $orig_cols) = ($rows, $cols);
    my $did_resize = 0;

    if ($RESIZE_TERM) {
        tui_request_term_resize(TUI_HEIGHT, TUI_WIDTH + 1);
        select(undef, undef, undef, 0.15);
        ($rows, $cols) = tui_term_size();
        $did_resize = ($rows != $orig_rows || $cols != $orig_cols);
    }

    if ($rows < TUI_HEIGHT || $cols < TUI_WIDTH) {
        print STDERR "${YELLOW}Terminal is ${cols}x${rows}; need at least " . TUI_WIDTH . "x" . TUI_HEIGHT . ".${RESET}\n";
        exit 1;
    }

    my %st = (
        stations       => \@STATIONS,
        current        => ($initial_idx // 0),
        track          => '',
        filter         => $initial_filter ? 1 : 0,
        mpv_pid        => undef,
        sock           => "/tmp/am_radio_tui_$$.sock",
        last_poll      => 0,
        msg            => '',
        msg_until      => 0,
        tune_start     => 0,
        req_id         => 1,
        search_mode    => 0,
        search_query   => '',
        search_results => [],
        search_page    => 0,
    );

    my $saved_term = tui_term_setup();
    print "\e[?1049h\e[?25l\e[2J\e[H";   # alt screen, hide cursor, clear

    my $cleaned = 0;
    my $cleanup = sub {
        return if $cleaned++;
        tui_stop_mpv(\%st);
        tui_term_restore($saved_term);
        print "\e[?25h\e[?1049l";         # show cursor, leave alt screen
        tui_request_term_resize($orig_rows, $orig_cols) if $did_resize;
    };
    local $SIG{INT}  = sub { $cleanup->(); exit 130 };
    local $SIG{TERM} = sub { $cleanup->(); exit 143 };
    local $SIG{HUP}  = sub { $cleanup->(); exit 129 };

    my $need_resize = 0;
    local $SIG{WINCH} = sub { $need_resize = 1 };

    tui_start_mpv(\%st);
    _set_msg(\%st, 'Tuning…', 1.5);

    # ---- event loop --------------------------------------------------------
    while (1) {

        # Handle terminal resize
        if ($need_resize) {
            $need_resize = 0;
            ($rows, $cols) = tui_term_size();
        }
        if ($rows < TUI_HEIGHT || $cols < TUI_WIDTH) {
            print "\e[2J\e[H";
            printf "${YELLOW}Terminal too small (%dx%d) — resize to at least %dx%d.${RESET}\n",
                   $cols, $rows, TUI_WIDTH, TUI_HEIGHT;
            sleep 0.3;
            next;
        }

        # Key handling
        if (defined(my $key = tui_read_key(0.05))) {
            if ($st{search_mode}) {
                if ($key eq 'esc') {
                    $st{search_mode} = 0; $st{search_query} = ''; $st{search_results} = []; $st{search_page} = 0;
                } elsif ($st{search_mode} == 2 && $key =~ /^[1-5]$/) {
                    tui_search_select(\%st, int($key));
                } elsif ($st{search_mode} == 2 && $key =~ /^[nN]$/) {
                    my $tp = int((scalar(@{ $st{search_results} }) - 1) / 5) + 1;
                    $st{search_page} = ($st{search_page} + 1) % $tp if $tp > 1;
                } elsif ($st{search_mode} == 2 && $key =~ /^[pP]$/) {
                    my $tp = int((scalar(@{ $st{search_results} }) - 1) / 5) + 1;
                    $st{search_page} = ($st{search_page} - 1 + $tp) % $tp if $tp > 1;
                } elsif ($st{search_mode} == 1) {
                    if    ($key eq "\n" || $key eq "\r")        { tui_do_search(\%st) }
                    elsif ($key eq "\x7f" || $key eq "\x08")   { $st{search_query} =~ s/.$//s }
                    elsif (length($key) == 1 && $key =~ /[ -~]/) { $st{search_query} .= $key }
                }
            } else {
                if    ($key eq 'q' || $key eq 'Q' || $key eq 'esc')    { last }
                elsif ($key eq 'right' || $key =~ /^[nN]$/)            { tui_change(\%st, +1) }
                elsif ($key eq 'left'  || $key =~ /^[pP]$/)            { tui_change(\%st, -1) }
                elsif ($key =~ /^[1-9]$/)                               { tui_jump(\%st, $key - 1) }
                elsif ($key =~ /^[oO]$/)                                { tui_toggle_filter(\%st) }
                elsif ($key =~ /^[rR]$/)                                { tui_retune(\%st) }
                elsif ($key =~ /^[iI]$/)                                { tui_dump_stream_info(\%st) }
                elsif ($key eq 'f' || $key eq '/')                      {
                    $st{search_mode} = 1; $st{search_query} = ''; $st{search_results} = [];
                }
            }
        }

        my $now = time();

        # Reap mpv if it died unexpectedly
        if ($st{mpv_pid} && waitpid($st{mpv_pid}, WNOHANG) == $st{mpv_pid}) {
            $st{mpv_pid}   = undef;
            _set_msg(\%st, 'Stream lost — press r to retune', 5);
        }

        # Poll ICY title every 1.5 s (skip during search to avoid contention)
        if ($now - $st{last_poll} >= 1.5 && $st{mpv_pid} && !$st{search_mode}) {
            my $t = tui_query_track(\%st);
            if (defined $t && $t ne ($st{track} // '')) {
                _verbose("TUI: Track changed to: $t");
            }
            $st{track}     = $t if defined $t;
            $st{last_poll} = $now;
        }

        tui_draw(\%st);
    }

    $cleanup->();
}

1;
