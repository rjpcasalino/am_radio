# am_radio — mobile app

A Flutter application that brings `am_radio.pl`'s internet radio player to
Linux desktop and Android, using the same station list and radio-browser.info
discovery API.

## Features

- Default station list matching `~/.radio_stations`
- Live search via [radio-browser.info](https://de1.api.radio-browser.info)
- Play / stop any stream
- "Now playing" bar

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

---

## Running on Android

1. Add the Android SDK to your Nix shell (see the `flake.nix` comments) **or**
   install it via Android Studio.
2. Set `ANDROID_HOME` / `ANDROID_SDK_ROOT`.
3. Enable USB debugging on your device, then:

```sh
cd mobile
flutter create . --platforms android   # first time only
flutter pub get
flutter run -d android
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
