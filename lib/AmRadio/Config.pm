package AmRadio::Config;

# ==============================================================================
# AmRadio::Config - station list management
#
# Handles:
#   * First-run bootstrap (writing the default ~/.radio_stations)
#   * Reading the config file into @STATIONS
#   * list_stations() display helper
#   * load_afn_stations() preset loader
# ==============================================================================

use strict;
use warnings;
use Exporter 'import';
use AmRadio::Colors qw(:all);

our $VERSION = '1.0.0';

our @EXPORT_OK = qw(
    load_stations
    list_stations
    load_afn_stations
    save_station
    $CONFIG_FILE
    @STATIONS
);

# Path to the user's station config file
our $CONFIG_FILE = "$ENV{HOME}/.radio_stations";

# In-memory station list.  Each entry is "Name::URL".
our @STATIONS;

# ------------------------------------------------------------------------------
# _bootstrap - write the default station list on first run
# ------------------------------------------------------------------------------
sub _bootstrap {
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
# load_stations - read $CONFIG_FILE into @STATIONS.  Bootstraps on first run.
# ------------------------------------------------------------------------------
sub load_stations {
    _bootstrap() unless -f $CONFIG_FILE;
    open(my $cfg, '<', $CONFIG_FILE) or die "Cannot open $CONFIG_FILE: $!";
    @STATIONS = ();
    while (my $line = <$cfg>) {
        chomp $line;
        next if $line =~ /^\s*$/;
        next if $line =~ /^\s*#/;
        push @STATIONS, $line;
    }
    close($cfg);
}

# ------------------------------------------------------------------------------
# list_stations - print the current station list with numbered entries
# ------------------------------------------------------------------------------
sub list_stations {
    for my $i (0 .. $#STATIONS) {
        my ($name) = split /::/, $STATIONS[$i], 2;
        printf "  %s%d)%s %s\n", $CYAN, $i + 1, $RESET, $name;
    }
}

# ------------------------------------------------------------------------------
# save_station - append a "Name::URL" entry to $CONFIG_FILE
# ------------------------------------------------------------------------------
sub save_station {
    my ($name, $url) = @_;
    open(my $fh, '>>', $CONFIG_FILE) or die "Cannot append to $CONFIG_FILE: $!";
    print $fh $name . '::' . $url . "\n";
    close($fh);
    push @STATIONS, $name . '::' . $url;
}

# ------------------------------------------------------------------------------
# load_afn_stations - replace @STATIONS with American Forces Network presets
# ------------------------------------------------------------------------------
sub load_afn_stations {
    print "${CYAN}Loading American Forces Network (AFN) stations...${RESET}\n";
    @STATIONS = (
        'AFN GO Tokyo::http://22963.live.streamtheworld.com/AFNP_TKO_SC',
        'AFN 360 Guantanamo Bay::http://27783.live.streamtheworld.com:3690/AFNE_GMO_SC',
        'AFN GO Humphreys The Eagle::http://14993.live.streamtheworld.com/AFNP_OSNAAC_SC',
        'AFN 360 Bahrain::http://27863.live.streamtheworld.com/AFNE_BHN_SC',
        'AFN 360 Benelux::http://28993.live.streamtheworld.com:3690/AFNE_BLX_SC',
        'AFN İncirlik::https://playerservices.streamtheworld.com/api/livestream-redirect/AFNE_ICK.mp3',
        'AFN 360 Bavaria::http://28563.live.streamtheworld.com/AFNE_BAV_SC',
        'AFN 360 Vicenza::http://23543.live.streamtheworld.com/AFNE_VIC_SC',
        'AFN 360 Wiesbaden::http://25453.live.streamtheworld.com:3690/AFNE_WBN_SC',
        'AFN GO Bahrain::https://playerservices.streamtheworld.com/api/livestream-redirect/AFNE_BHNAAC.aac',
    );
    printf "${GREEN}Loaded %d AFN radio stations.${RESET}\n", scalar @STATIONS;
    print "${DIM}American Forces Network - Serving U.S. military worldwide${RESET}\n\n";
}

1;
