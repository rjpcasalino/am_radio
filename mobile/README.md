# am_radio — mobile app

A Flutter application that brings `am_radio.pl`'s internet radio player to
Linux desktop, Android, and iOS, using the same station list and radio-browser.info
discovery API.

## Features

- Default station list matching `~/.radio_stations`
- Live search via [radio-browser.info](https://de1.api.radio-browser.info)
- Play / stop any stream
- "Now playing" bar
- **Custom ASCII art logo** — Vintage radio design matching the bakelite theme

## App Icon

The app uses a custom ASCII art logo featuring a vintage radio design:

```
   !
 __║__
[●─⊙─●]
| A M |
|≈≈≈≈≈|
'-----'
```

The icon uses the app's vintage bakelite color palette (amber #E8A020 on dark brown #1A0F00).

To regenerate the icon after making changes:
```sh
cd mobile
nix develop ..#mobile
./assets/generate_icons.sh
```

---

## Quick Start — Deploy to Your Device

Choose your platform:

- **[iOS (iPhone)](#running-on-ios-iphone-via-usb-c)** — Requires macOS + Xcode + free Apple ID
- **[Android](#running-on-android-device-via-usb)** — Requires Android SDK + USB debugging
- **[Linux desktop](#running-on-linux)** — Requires mpv

Each section includes complete setup instructions and optional steps for building release builds.

---

## Development on NixOS / macOS

A Nix flake is provided at the repo root.  Enter the Flutter dev shell:

```sh
# from the repo root
nix develop .#mobile
```

The shell will:
1. Put Flutter, cmake, ninja, clang, pkg-config, gtk3, and mpv on your PATH.
2. Automatically scaffold the `linux/` and `android/` platform directories
   the first time you enter (runs `flutter create . --platforms linux,android`).
3. **macOS only:** restore `DEVELOPER_DIR`, prepend `$DEVELOPER_DIR/usr/bin`
   to `PATH`, and unset `SDKROOT` so that `xcodebuild` and other Xcode
   command-line tools work correctly inside the Nix shell.
4. **macOS only:** run `chmod -R u+w mobile/ios/` if that directory exists, so
   CocoaPods can rewrite the workspace files it needs during `pod install`.

> **macOS / xcodebuild note:** two things break `xcodebuild` inside `nix develop`:
>
> 1. `DEVELOPER_DIR` is unset — `/usr/bin/xcodebuild` is an `xcrun` shim that
>    needs `DEVELOPER_DIR` to find the real toolchain inside `Xcode.app`.
> 2. Nix's `clang` wrapper (pulled in via `buildInputs`) sets `SDKROOT` to a
>    Nix-store SDK path.  `xcrun` then searches that path for tools and reports
>    *"tool 'xcodebuild' not found"* even if `DEVELOPER_DIR` is correct.
>    Unsetting `SDKROOT` lets `xcrun` fall back to the Xcode SDK automatically.
>
> The shell hook handles both: it re-exports `DEVELOPER_DIR` via
> `xcode-select -p` and runs `unset SDKROOT`.

---

## Running on Linux

```sh
cd mobile
flutter pub get
flutter run -d linux
```

`mpv` must be on your PATH (it is in the Nix dev shell).

### Stopping the app (no desktop environment)

When running headless (no window manager / no display), close the app with any
of the standard POSIX signals — the app registers handlers for all three and
ensures `mpv` is killed before exiting:

| How | Signal |
|-----|--------|
| `Ctrl+C` in the terminal | `SIGINT` |
| `kill <pid>` | `SIGTERM` |
| SSH session ends / terminal closes | `SIGHUP` |

```sh
# find the PID
pgrep -f am_radio

# then kill it cleanly
kill <pid>
```

Or just press `Ctrl+C` in the same terminal where `flutter run` was started.

## Running on iOS (iPhone via USB-C)

### Prerequisites

| Requirement | Notes |
|-------------|-------|
| macOS with **Xcode 15+** | Required for iOS builds |
| **CocoaPods** | `sudo gem install cocoapods` |
| iPhone running **iOS 16+** | |
| **USB-C cable** | |
| Free **Apple ID** | No paid developer account needed for personal-device testing |

### Step 1 — Install Xcode command-line tools

```sh
xcode-select --install
```

Open Xcode at least once and accept the license agreement.

### Step 2 — Add the iOS platform to the project

```sh
cd mobile
flutter create . --platforms ios
```

This generates the `ios/` directory.

### Step 3 — Install dependencies (Flutter + CocoaPods)

```sh
flutter pub get

# Flutter creates some ios/ files read-only (mode 444); fix that before
# CocoaPods tries to rewrite Runner.xcworkspace/contents.xcworkspacedata.
chmod -R u+w ios/

cd ios && pod install && cd ..
```

### Step 4 — Sign the app with your Apple ID

1. Open the workspace in Xcode:

   ```sh
   open ios/Runner.xcworkspace
   ```

2. Select the **Runner** target → **Signing & Capabilities** tab.
3. Under **Team**, choose your personal Apple ID. Xcode creates a free
   provisioning profile automatically.

### Step 5 — Trust the developer certificate on your iPhone

1. On your iPhone: **Settings → General → VPN & Device Management**
2. Tap your Apple ID → **Trust**

_(You only need to do this once per Mac / Apple ID pair.)_

### Step 6 — Connect the iPhone and run

```sh
# List detected devices — confirm your iPhone appears
flutter devices

# Run on the connected iPhone
flutter run -d <device-id-from-above>

# Or let Flutter pick the only connected device automatically
flutter run
```

### Optional: background audio while screen is locked

Add the `audio` background mode to `ios/Runner/Info.plist` inside `<dict>`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

### Step 7 (Optional) — Build a release IPA for distribution

For a production build without debug overhead:

```sh
cd mobile

# Build release IPA (requires signing with your Apple ID as configured in Step 4)
flutter build ipa --release

# The IPA will be at:
# build/ios/ipa/am_radio.ipa
```

#### Install the release IPA on your device

**Note:** Installing an IPA built with a free Apple ID requires Xcode. Apps signed with a free provisioning profile expire after 7 days and need to be reinstalled.

```sh
# Connect your iPhone via USB, then install via Xcode command line:
cd mobile/ios
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -destination 'platform=iOS,id=<your-device-udid>' \
  -allowProvisioningUpdates \
  install

# To find your device UDID:
flutter devices
# or
xcrun xctrace list devices
```

**Alternative:** Open `ios/Runner.xcworkspace` in Xcode, select your device from the device menu, and click the Run button with the Release scheme selected.

---

## Running on Android (device via USB)

### Quick Start: Automated Deployment

For a one-command deployment to your Android device with automatic screenshot capture, use the provided automation script:

```sh
# From the repo root
./deploy-android.sh

# Or with Nix:
nix run .#deploy-android

# Build release version with custom screenshot directory
./deploy-android.sh --release --screenshot-dir ~/Pictures
```

This script will:
1. Build the Flutter APK (debug or release)
2. Install it on your connected Android device
3. Launch the app
4. Capture a screenshot from the device
5. Transfer the screenshot to your PC

The script requires an Android device connected via USB with USB debugging enabled. See [manual setup instructions](#manual-setup-android) below for first-time device configuration.

---

### Manual Setup: Android

### Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Android SDK** | Install via Android Studio or add to Nix shell (see `flake.nix`) |
| **Android device** running **Android 5.0+** (API 21+) | |
| **USB cable** | |
| **USB debugging enabled** | See setup steps below |

### Step 1 — Install Android SDK and set environment variables

#### Option A: Via Android Studio (recommended)

1. Download and install [Android Studio](https://developer.android.com/studio)
2. Open Android Studio → **Settings/Preferences → Appearance & Behavior → System Settings → Android SDK**
3. Install at least one Android SDK platform (API 21+)
4. Note the SDK location path

#### Option B: Via Nix shell

Add the Android SDK to your Nix shell — see comments in `flake.nix` at the repo root.

#### Set environment variables

```sh
export ANDROID_HOME="$HOME/Android/Sdk"      # or your SDK path
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$PATH:$ANDROID_HOME/platform-tools"
```

Add these to your `~/.bashrc` or `~/.zshrc` to persist across sessions.

### Step 2 — Enable USB debugging on your Android device

1. **Settings → About phone** → Tap **Build number** 7 times to enable Developer options
2. **Settings → System → Developer options** (or **Settings → Developer options**)
3. Enable **USB debugging**
4. Connect your device via USB
5. On your device, accept the **"Allow USB debugging?"** prompt and check **"Always allow from this computer"**

### Step 3 — Verify device connection

```sh
# Check that adb can see your device
adb devices
```

You should see output like:
```
List of devices attached
A1B2C3D4E5F6    device
```

If you see `unauthorized`, check your device for the USB debugging prompt.

### Step 4 — Add the Android platform (first time only)

```sh
cd mobile
flutter create . --platforms android
```

This generates the `android/` directory with the app configuration already set up for cleartext HTTP traffic (required for radio streams).

### Step 5 — Install dependencies and run on device

```sh
flutter pub get

# List connected devices to verify Flutter can see your phone
flutter devices

# Run on the connected Android device
flutter run -d android

# Or specify the device ID if multiple devices are connected
flutter run -d <device-id-from-flutter-devices>
```

The app will be built, installed, and launched on your device. Hot reload is enabled by default — press `r` in the terminal to reload after making code changes.

### Step 6 (Optional) — Build a release APK

For a production build without debug overhead:

```sh
cd mobile

# Build release APK
flutter build apk --release

# The APK will be at:
# build/app/outputs/flutter-apk/app-release.apk
```

#### Install the release APK on your device

```sh
# Install via adb
adb install build/app/outputs/flutter-apk/app-release.apk

# Or transfer the APK to your device and install it manually:
# 1. Copy app-release.apk to your device (via USB, email, etc.)
# 2. On your device: tap the APK file and confirm installation
# 3. You may need to enable "Install from unknown sources" in Settings
```

### Android cleartext HTTP

Many radio stations stream over plain HTTP (`http://`). Android 9+ (API 28)
blocks cleartext traffic by default, which causes a
`CleartextNotPermittedException` when ExoPlayer tries to open an `http://` URL.

The repository already ships
`android/app/src/main/AndroidManifest.xml` and
`android/app/src/main/res/xml/network_security_config.xml` with cleartext
traffic enabled, so `flutter create . --platforms android` will not overwrite
them.

If you have an existing `android/` directory that was generated before this fix
was added, patch it manually:

```sh
# 1. Add the networkSecurityConfig attribute to the application tag
#    (only if not already present)
grep -q 'networkSecurityConfig=' android/app/src/main/AndroidManifest.xml || \
  sed -i 's|<application|<application android:networkSecurityConfig="@xml/network_security_config"|' \
      android/app/src/main/AndroidManifest.xml

# 2. Create the config file
mkdir -p android/app/src/main/res/xml
cat > android/app/src/main/res/xml/network_security_config.xml << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="true" />
</network-security-config>
EOF
```

The Nix `mobile` dev shell applies this patch automatically.

---

## Project layout

```
mobile/
├── lib/
│   ├── main.dart                  # app entry, Provider setup
│   ├── models/
│   │   └── station.dart           # Station data class
│   ├── screens/
│   │   └── home_screen.dart       # station list + search UI
│   └── services/
│       └── player_service.dart    # mpv subprocess player (Linux)
├── pubspec.yaml
└── analysis_options.yaml
```

Platform directories (`linux/`, `android/`) are generated by
`flutter create . --platforms linux,android` and are excluded from version
control via `.gitignore`.
