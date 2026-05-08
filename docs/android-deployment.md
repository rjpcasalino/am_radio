# Android Deployment Automation

## Overview

The `deploy-android.sh` script provides one-command deployment of the Flutter mobile app to Android devices with automatic screenshot capture for documentation purposes.

## Usage

### Basic Usage

```sh
# From the repository root
./deploy-android.sh
```

Or with Nix:

```sh
nix run .#deploy-android
```

### Options

- `--release` — Build release APK instead of debug (default: debug)
- `--screenshot-dir DIR` — Directory to save screenshot (default: current directory)
- `--skip-build` — Skip the build step (useful if you just want to install an already-built APK)
- `--help` — Show help message

### Examples

```sh
# Build and deploy release version
./deploy-android.sh --release

# Deploy and save screenshot to specific directory
./deploy-android.sh --screenshot-dir ~/Pictures/app-screenshots

# Just install and screenshot (skip build)
./deploy-android.sh --skip-build
```

## What It Does

The script automates the entire deployment and documentation workflow:

1. **Prerequisites Check** — Verifies Flutter and adb are available
2. **Device Detection** — Checks for connected Android devices with USB debugging enabled
3. **Build** — Runs `flutter build apk` (debug or release mode)
4. **Install** — Installs the APK on the connected device using `adb install`
5. **Launch** — Starts the app on the device
6. **Screenshot** — Captures a screenshot from the device
7. **Transfer** — Pulls the screenshot to your PC and cleans up the device

## Prerequisites

Before running the script:

1. **Android device** connected via USB
2. **USB debugging** enabled on the device
3. **Flutter** installed (available automatically in `nix develop .#mobile`)
4. **Android SDK** with platform-tools (adb) installed

See [mobile/README.md](mobile/README.md) for detailed setup instructions.

## Integration with Nix

The script is integrated into the Nix flake as an app, which means:

- It can be run with `nix run .#deploy-android` without entering the dev shell
- All dependencies (Flutter, Android SDK, adb) are automatically provided
- The script is reproducible across different systems

## Implementation Details

### Package Name

The script uses the default Flutter package name structure: `com.example.am_radio`

If you change the package name in `mobile/android/app/build.gradle`, update the `package_name` variable in the `launch_app()` function.

### Screenshot Timing

The script waits 5 seconds after launching the app before taking a screenshot. This gives the app time to fully render. Adjust the sleep duration in the `launch_app()` function if needed.

### Screenshot Naming

Screenshots are saved with a timestamp: `am_radio_android_YYYYMMDD_HHMMSS.png`

This prevents overwriting previous screenshots and makes it easy to track versions.

## Troubleshooting

### Device not detected

```
No Android device connected or authorized
```

**Solution:**
1. Check USB cable connection
2. Enable USB debugging in Developer options
3. Accept the "Allow USB debugging?" prompt on your device
4. Run `adb devices` to verify connection

### App won't launch

```
Error: Activity class ... does not exist
```

**Solution:** The package name may have changed. Check `mobile/android/app/src/main/AndroidManifest.xml` and update the script's `package_name` variable.

### Screenshot is black or empty

**Solution:** Increase the sleep duration in the `launch_app()` function to give the app more time to render.

## Future Enhancements

Possible improvements to consider:

- [ ] Support multiple connected devices (currently uses first device)
- [ ] Add option to record video instead of screenshot
- [ ] Automated UI testing with espresso or flutter_driver
- [ ] Upload screenshots to cloud storage or documentation site
- [ ] Generate release notes from commit messages
