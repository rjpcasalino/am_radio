#!/usr/bin/env bash
set -euo pipefail

# deploy-android.sh — Build Flutter app, install on Android device, and capture screenshot
#
# Usage:
#   ./deploy-android.sh [--release] [--screenshot-dir DIR] [--wait SECONDS]
#
# Options:
#   --release          Build release APK instead of debug (default: debug)
#   --screenshot-dir   Directory to save screenshot (default: current directory)
#   --wait SECONDS     Seconds to wait for app to render before screenshot (default: 10)
#   --skip-build       Skip building the app
#   --help             Show this help message

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
BUILD_MODE="debug"
SCREENSHOT_DIR="."
SKIP_BUILD=false
RENDER_DELAY=10  # seconds to wait for app to render before screenshot

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            BUILD_MODE="release"
            shift
            ;;
        --screenshot-dir)
            SCREENSHOT_DIR="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --wait)
            RENDER_DELAY="$2"
            shift 2
            ;;
        --help)
            grep "^#" "$0" | grep -v "#!/" | sed 's/^# //'
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            exit 1
            ;;
    esac
done

log_info() {
    echo -e "${BLUE}➜${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v flutter &> /dev/null; then
        log_error "flutter not found. Please install Flutter or run 'nix develop .#mobile'"
        exit 1
    fi

    if ! command -v adb &> /dev/null; then
        log_error "adb not found. Please install Android SDK platform-tools"
        exit 1
    fi

    log_success "Prerequisites OK"
}

# Check for connected Android device
check_device() {
    log_info "Checking for connected Android device..."

    local devices=$(adb devices | grep -v "List of devices" | grep "device$" | wc -l)

    if [ "$devices" -eq 0 ]; then
        log_error "No Android device connected or authorized"
        echo ""
        echo "Please:"
        echo "  1. Connect your Android device via USB"
        echo "  2. Enable USB debugging in Developer options"
        echo "  3. Accept the 'Allow USB debugging' prompt on your device"
        echo "  4. Run 'adb devices' to verify connection"
        exit 1
    fi

    log_success "Found $devices connected device(s)"

    # Get device info
    local device_id=$(adb devices | grep "device$" | head -n1 | awk '{print $1}')
    local device_model=$(adb -s "$device_id" shell getprop ro.product.model 2>/dev/null | tr -d '\r\n' || echo "Unknown")
    local android_version=$(adb -s "$device_id" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r\n' || echo "Unknown")

    echo "  Device: $device_model (Android $android_version)"
    echo "  ID: $device_id"
    echo ""
}

# Build the Flutter app
build_app() {
    if [ "$SKIP_BUILD" = true ]; then
        log_info "Skipping build (--skip-build specified)"
        return
    fi

    log_info "Building Flutter app ($BUILD_MODE mode)..."

    cd mobile

    # Get dependencies first
    flutter pub get

    # Build APK
    if [ "$BUILD_MODE" = "release" ]; then
        flutter build apk --release
        APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
    else
        flutter build apk --debug
        APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
    fi

    cd ..

    if [ ! -f "mobile/$APK_PATH" ]; then
        log_error "APK not found at mobile/$APK_PATH"
        exit 1
    fi

    log_success "Build complete: mobile/$APK_PATH"
}

# Install the app on the device
install_app() {
    log_info "Installing app on device..."

    if [ "$BUILD_MODE" = "release" ]; then
        APK_PATH="mobile/build/app/outputs/flutter-apk/app-release.apk"
    else
        APK_PATH="mobile/build/app/outputs/flutter-apk/app-debug.apk"
    fi

    if [ ! -f "$APK_PATH" ]; then
        log_error "APK not found at $APK_PATH"
        exit 1
    fi

    adb install -r "$APK_PATH"

    log_success "App installed successfully"
}

# Launch the app
launch_app() {
    log_info "Launching app on device..."

    # Try to find the package name from gradle files, fallback to default
    local package_name="com.example.am_radio"

    if [ -f "mobile/android/app/build.gradle" ]; then
        # Try to extract from build.gradle
        local gradle_pkg=$(grep -E "^\s*namespace\s+" mobile/android/app/build.gradle | sed -E 's/.*namespace\s+"([^"]+)".*/\1/' || true)
        if [ -n "$gradle_pkg" ]; then
            package_name="$gradle_pkg"
        fi
    fi

    log_info "Using package name: $package_name"

    # Start the main activity
    adb shell am start -n "$package_name/.MainActivity"

    log_success "App launched"

    # Give the app time to fully render
    log_info "Waiting for app to render (${RENDER_DELAY} seconds)..."
    sleep "$RENDER_DELAY"
}

# Capture screenshot from device
capture_screenshot() {
    log_info "Capturing screenshot from device..."

    # Create screenshot directory if it doesn't exist
    mkdir -p "$SCREENSHOT_DIR"

    # Generate filename with timestamp
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local remote_path="/sdcard/am_radio_screenshot_${timestamp}.png"
    local local_path="$SCREENSHOT_DIR/am_radio_android_${timestamp}.png"

    # Take screenshot on device
    adb shell screencap -p "$remote_path"

    # Pull screenshot to PC
    adb pull "$remote_path" "$local_path"

    # Clean up screenshot from device
    adb shell rm "$remote_path"

    log_success "Screenshot saved to: $local_path"

    # Try to open the screenshot if we have a viewer
    if command -v xdg-open &> /dev/null; then
        log_info "Opening screenshot..."
        xdg-open "$local_path" 2>/dev/null &
    elif command -v open &> /dev/null; then
        log_info "Opening screenshot..."
        open "$local_path" 2>/dev/null &
    fi
}

# Main execution
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  am_radio — Android Deployment & Screenshot Tool     ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""

    # Check we're in the right directory
    if [ ! -f "flake.nix" ] || [ ! -d "mobile" ]; then
        log_error "Must run from the repository root directory"
        exit 1
    fi

    check_prerequisites
    check_device
    build_app
    install_app
    launch_app
    capture_screenshot

    echo ""
    log_success "Deployment complete!"
    echo ""
    echo "The am_radio app is now running on your Android device."
    echo "Screenshot has been captured and saved to your PC."
    echo ""
}

main
