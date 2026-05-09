#!/usr/bin/env bash
set -euo pipefail

# deploy-ios.sh — Build the Flutter app and install it on a connected iPhone
#
# Usage (from the repo root):
#   bash deploy-ios.sh [options]
#
# Options:
#   --release        Build a release IPA instead of debug (default: debug)
#   --device-id ID   Target a specific device UUID (default: auto-detect first iPhone)
#   --skip-build     Skip the build step (use a previously built .app)
#   --help           Show this help message
#
# Prerequisites — one of:
#   A) Free Apple ID (no paid account):
#      - Open Xcode → Preferences → Accounts → add your Apple ID
#      - Xcode will create a free "Personal Team" provisioning profile
#      - The app must be reinstalled every 7 days
#   B) Apple Developer account ($99/year):
#      - Set DEVELOPMENT_TEAM in Xcode project settings
#      - Allows AdHoc / TestFlight distribution
#
# Quickstart:
#   1.  Connect iPhone via USB and trust the computer when prompted
#   2.  nix develop .#mobile          # enter the Flutter dev shell
#   3.  bash deploy-ios.sh            # build (debug) and install
#   4.  bash deploy-ios.sh --release  # build release and install
#
# If Xcode has never built for your device, run once from Xcode to create the
# free provisioning profile, then use this script for subsequent installs.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BUILD_MODE="debug"
DEVICE_ID=""
SKIP_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            BUILD_MODE="release"
            shift
            ;;
        --device-id)
            DEVICE_ID="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help)
            grep "^#" "$0" | grep -v "#!/" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            exit 1
            ;;
    esac
done

log_info()    { echo -e "${BLUE}➜${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warn()    { echo -e "${YELLOW}⚠${NC} $1"; }
log_error()   { echo -e "${RED}✗${NC} $1"; }

check_prerequisites() {
    log_info "Checking prerequisites..."

    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "iOS deployment requires macOS with Xcode installed."
        exit 1
    fi

    if ! command -v flutter &> /dev/null; then
        log_error "flutter not found. Run: nix develop .#mobile"
        exit 1
    fi

    if ! xcode-select -p &> /dev/null; then
        log_error "Xcode command-line tools not found. Run: xcode-select --install"
        exit 1
    fi

    log_success "Prerequisites OK (Flutter $(flutter --version --machine 2>/dev/null | grep -o '"frameworkVersion":"[^"]*"' | cut -d'"' -f4 || echo '?'))"
}

detect_device() {
    log_info "Scanning for connected iOS devices..."

    # flutter devices output format (fields separated by ' • '):
    #   <name> • <device-id> • <platform> • <os version>
    # We filter for real iOS hardware (not simulators) then parse field 2.
    local raw_devices
    raw_devices=$(flutter devices 2>/dev/null \
        | grep -i " ios " \
        | grep -iv "simulator" \
        || true)

    if [[ -z "$raw_devices" ]]; then
        log_error "No iOS device found."
        echo ""
        echo "  Please:"
        echo "    1. Connect your iPhone via USB"
        echo "    2. Tap 'Trust' on the iPhone when prompted"
        echo "    3. Unlock the iPhone"
        echo "    4. Run: flutter devices   (to verify Flutter sees it)"
        exit 1
    fi

    echo "$raw_devices"
    echo ""

    if [[ -z "$DEVICE_ID" ]]; then
        # Device ID is the second ' • '-delimited field on the first matching line.
        DEVICE_ID=$(echo "$raw_devices" \
            | head -n1 \
            | awk -F' • ' '{print $2}' \
            | xargs)   # strip surrounding whitespace
    fi

    if [[ -z "$DEVICE_ID" ]]; then
        log_error "Could not determine device ID. Use --device-id <UUID> to specify explicitly."
        exit 1
    fi

    log_success "Target device: $DEVICE_ID"
}

build_app() {
    if [[ "$SKIP_BUILD" == true ]]; then
        log_info "Skipping build (--skip-build specified)"
        return
    fi

    log_info "Building Flutter app (mode: $BUILD_MODE)..."
    cd mobile

    # Flutter rewrites ios/Flutter/Debug.xcconfig and Release.xcconfig during
    # pub get.  If git checked them out read-only (common on macOS), the write
    # fails.  Ensure they are writable before proceeding.
    chmod u+w ios/Flutter/Debug.xcconfig ios/Flutter/Release.xcconfig 2>/dev/null || true

    flutter pub get

    if [[ "$BUILD_MODE" == "release" ]]; then
        # Release builds need a signing identity; use --no-codesign for ad-hoc
        # local installs, then re-sign with Xcode if you have a developer account.
        log_warn "Release mode: building without code signing."
        log_warn "If install fails, open ios/Runner.xcworkspace in Xcode,"
        log_warn "set a Development Team, then use Product → Run."
        flutter build ios --release --no-codesign
    else
        flutter build ios --debug
    fi

    cd ..
    log_success "Build complete"
}

install_app() {
    log_info "Installing on device $DEVICE_ID ..."

    cd mobile

    # 'flutter install' copies the built .app bundle to the device via ios-deploy.
    # For a debug build this also starts the app; for release it just installs.
    flutter install --device-id "$DEVICE_ID"

    cd ..
    log_success "App installed successfully"
}

main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║      am_radio — iOS Deployment Tool                  ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    if [[ ! -f "flake.nix" ]] || [[ ! -d "mobile" ]]; then
        log_error "Must be run from the repository root directory"
        exit 1
    fi

    check_prerequisites
    detect_device
    build_app
    install_app

    echo ""
    log_success "Done! am_radio is installed on your iPhone."
    echo ""
    echo "  To launch:        open the app from the Home Screen"
    echo "  To re-deploy:     bash deploy-ios.sh"
    echo "  Release build:    bash deploy-ios.sh --release"
    echo ""
    if [[ "$BUILD_MODE" == "debug" ]]; then
        log_warn "Debug builds expire after 7 days (free Apple ID) or never (paid account)."
        log_warn "Reinstall with 'bash deploy-ios.sh' when the app stops launching."
    fi
}

main
