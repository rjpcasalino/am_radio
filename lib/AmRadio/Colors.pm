package AmRadio::Colors;

# ==============================================================================
# AmRadio::Colors - ANSI terminal color/style constants
#
# A single source of truth for all escape sequences used throughout am_radio.
# Importers get a flat list of scalars via the default export tag ':all'.
# ==============================================================================

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    $CYAN $GREEN $YELLOW $RED $MAGENTA $WHITE
    $BOLD $DIM $RESET
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

our $CYAN    = "\e[36m";
our $GREEN   = "\e[32m";
our $YELLOW  = "\e[33m";
our $RED     = "\e[31m";
our $MAGENTA = "\e[35m";
our $WHITE   = "\e[37m";
our $BOLD    = "\e[1m";
our $DIM     = "\e[2m";
our $RESET   = "\e[0m";

1;
