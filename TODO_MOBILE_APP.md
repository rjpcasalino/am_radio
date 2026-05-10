# Mobile App Development Plans

The goal is to turn this into a useful mobile application.  We are using
**Flutter** so that one Dart codebase covers both Linux desktop (for NixOS
development) and Android, with iOS possible later.

## Tech stack

| Platform | Status |
|----------|--------|
| Linux desktop (Flutter) | ✅ MVP scaffolded — see `mobile/` |
| Android (Flutter) | 🚧 scaffold ready; audio backend needs device testing |
| iOS (Flutter) | 🚧 Xcode project committed; ready to install on device |

## NixOS / Nix flake

A `flake.nix` lives at the repo root.  Enter the Flutter dev shell with:

```sh
nix develop .#mobile
```

On macOS this sets `DEVELOPER_DIR` automatically so Xcode tools are on PATH.
On Linux it installs Flutter with the Android SDK, cmake, ninja, clang, etc.

## Flutter app (`mobile/`)

### Done
- [x] `flake.nix` — `devShells.mobile` with all Linux + Android build deps
- [x] `mobile/pubspec.yaml` — Flutter project metadata (Android, iOS, Linux)
- [x] `mobile/lib/main.dart` — app entry + dark Material 3 theme (vintage bakelite)
- [x] `mobile/lib/models/station.dart` — Station data class (config + JSON)
- [x] `mobile/lib/services/player_service.dart` — mpv subprocess (Linux) + just_audio/AVFoundation (iOS/Android)
- [x] `mobile/lib/screens/home_screen.dart` — station list + radio-browser search
- [x] `mobile/lib/widgets/frequency_dial.dart` — horizontal AM-band dial (tap/swipe to tune)
- [x] `mobile/lib/widgets/radio_logo.dart` — hand-drawn transistor radio logo (header)
- [x] `mobile/lib/widgets/signal_meter.dart` — animated signal-strength bar meter
- [x] `mobile/lib/services/station_repository.dart` — persist saved stations via SharedPreferences
- [x] `mobile/lib/services/settings_service.dart` — persist settings (minimal mode, list/radio view)
- [x] Minimal (A4-paper) mode: white background, black text, no logo — toggle from header
- [x] List / radio view toggle: "list" = simple station list; "radio" = frequency dial + list
- [x] `FrequencyDial` widget wired into radio (dial) view — tap tick or swipe to change station
- [x] `.github/workflows/flutter.yml` — CI: analyze + test (Linux); `flutter build ios --no-codesign` (macOS)
- [x] `mobile/ios/` — Xcode runner directory committed; app icons populated
- [x] `Info.plist` — `UIBackgroundModes: audio` (radio keeps playing when screen locks)
- [x] `Info.plist` — `NSAppTransportSecurity` allowsArbitraryLoads (HTTP radio streams work)
- [x] `Podfile` + `project.pbxproj` — iOS deployment target 14.0 (required by just_audio 0.10.x)
- [x] `deploy-ios.sh` — one-command physical iPhone install (see below)

### iOS — Getting the app on your iPhone

**Quickstart (free Apple ID, no $99 developer account needed):**

1. **First time only** — open Xcode, go to **Preferences → Accounts**, add your
   Apple ID.  Xcode creates a free "Personal Team" that lets you install on
   your own devices.

2. **Trust your Mac** — connect iPhone via USB and tap *Trust* when prompted.

3. **Enter the dev shell** (macOS only, needs Flutter + Xcode):
   ```sh
   nix develop .#mobile
   ```

4. **Deploy** from the repo root:
   ```sh
   bash deploy-ios.sh            # debug build (default)
   bash deploy-ios.sh --release  # release build
   ```

The script auto-detects your connected iPhone, runs `flutter pub get`, builds
the app, and calls `flutter install` to copy it to the device.

> **7-day expiry (free account):** debug builds signed with a free Personal
> Team profile expire after 7 days.  Simply re-run `bash deploy-ios.sh` to
> reinstall.  Release builds without a paid account also expire the same way —
> use the `--release` flag for a faster, smaller binary.

**Alternatively** — open `mobile/ios/Runner.xcworkspace` in Xcode, select
your device, and press ▶ (Run).  This is equivalent to debug deploy.

### Next — Features / Platform
- [ ] Verify `flutter build ios --no-codesign` passes in CI (macOS GitHub runner)
- [ ] Android audio backend: test `just_audio` + ExoPlayer on a real device
- [ ] Show live track metadata (ICY tags) in the Now Playing bar
- [ ] Lo-Fi AM filter toggle (pass `--af=…` to mpv on Linux; EQ plugin on mobile)

### Next — UI
- [ ] Full transistor radio redesign for the main (radio) view:
      knob widgets (volume, tone), grille texture, curved body, backlit dial window
- [ ] Minimal mode: refine A4-paper print feel (hairline rules, bold name, italic genre)
- [ ] Dark-mode variant of minimal mode (white-on-black terminal aesthetic)

### iOS — Deployment pain points

**Code signing / trust workflow issues:**

The current workflow for installing on iOS with a free Apple ID requires:
1. Opening Xcode to add Apple ID (one-time)
2. USB connection + trusting the Mac
3. Running deploy script or Xcode
4. **Manually trusting the developer certificate on the physical device** (Settings → General → VPN & Device Management → Developer App → Trust)
5. Re-signing and reinstalling every 7 days when the certificate expires

**Ideas to improve:**
- [ ] **Automated certificate trust prompt**: Investigate if there's a way to programmatically trigger the trust dialog or provide clearer post-install instructions
- [ ] **TestFlight distribution**: For testers with Apple IDs, distributing via TestFlight removes the 7-day expiry and trust step (requires paid Apple Developer account $99/yr)
- [ ] **Enterprise distribution**: For organizations, Apple Developer Enterprise Program allows in-house app distribution without App Store (requires special approval + $299/yr)
- [ ] **Clearer documentation**: Add screenshots to the TODO/README showing the Settings → General → VPN & Device Management path, as this step is not obvious
- [ ] **Post-install notification**: Add a Flutter dialog on first launch that detects untrusted cert state and guides user to Settings
- [ ] **Deploy script enhancement**: Have `deploy-ios.sh` print the exact Settings path and wait for user confirmation before exiting
- [ ] **CI/CD integration**: Explore GitHub Actions self-hosted runner on macOS with provisioning profiles for automated TestFlight uploads

**Current workaround:**
Users must manually navigate to Settings and trust the certificate after each install. This is an iOS platform limitation for apps signed with free Personal Team certificates.

### Performance — App startup optimization

**Current implementation:**
The app already implements async loading (see `mobile/lib/main.dart:76-102`):
- Services (LogService, SettingsService, PlayerService, StationRepository) are instantiated synchronously before `runApp()`
- Settings and saved stations are loaded asynchronously AFTER `runApp()` via `settingsService.load()` and `stations.load()`
- This should display the UI immediately with default stations while data loads in the background

**Potential causes of perceived startup delay:**
- [ ] **Widget build overhead**: First frame may be delayed by complex widget tree (FrequencyDial, SignalMeter, RadioLogo)
- [ ] **SharedPreferences I/O**: Even though async, the platform channel call might briefly block on slower devices
- [ ] **Provider initialization**: MultiProvider with 4 ChangeNotifiers might add overhead
- [ ] **iOS-specific**: AVFoundation/AudioPlayer initialization, though currently lazy (created on first play)
- [ ] **Theme/font loading**: Material 3 theme and monospace font might delay first frame
- [ ] **Splash screen not configured**: iOS might be showing a blank screen instead of a proper splash

**Ideas to improve startup time:**
- [x] **Add iOS launch storyboard**: `LaunchScreen.storyboard` updated — dark bakelite background (#1A0F00) with centred "AM·RADIO" label in amber
- [ ] **Profile startup with Flutter DevTools**: Use Timeline view to identify which widgets/services are taking the most time in the first frame
- [ ] **Lazy-load heavy widgets**: Defer rendering FrequencyDial/SignalMeter until after first frame using `FutureBuilder` or `addPostFrameCallback`
- [ ] **Precompile RegExp/constants**: Move any runtime parsing/computation in widget build methods to static initialization
- [ ] **Reduce initial widget tree depth**: Show a simplified UI skeleton first, then swap in full widgets after loaded
- [ ] **Isolate for I/O**: Move SharedPreferences reads to a separate isolate to avoid any main-thread blocking (likely overkill for small data)
- [ ] **Profile SharedPreferences overhead**: Log timestamps around `prefs.getString()` calls to measure actual I/O time
- [ ] **Enable impeller on iOS**: Flutter's new rendering engine (enabled by default in recent Flutter versions) may improve first-frame time
- [ ] **Measure baseline**: Add more detailed logging around widget build phases (initState, build, first paint) to quantify the delay

**Recommended first steps:**
1. Profile with Flutter DevTools Timeline to identify actual bottlenecks
2. Add iOS launch storyboard for immediate visual feedback
3. Log first-frame timing in `main.dart` after `runApp()` returns

## iOS — Decision record

**Chosen: Flutter (extend existing codebase, add `--platforms ios`)**

Reasons:
- `player_service.dart` already implements the iOS audio path: the `else`
  branch (everything that isn't `Platform.isLinux`) uses `just_audio`,
  which wraps AVFoundation — the correct native backend. ICY metadata,
  buffering state, and play/stop all work through that path already.
- `pubspec.yaml` already depends on `just_audio ^0.10.5` (supports iOS),
  already declares `ios: true` for launcher icons, and already has a
  1024×1024 icon asset.
- All UI widgets (`FrequencyDial`, `RadioLogo`, `SignalMeter`) and all
  services (`SettingsService`, `StationRepository`) are pure Dart with no
  platform-specific code — they run on iOS unchanged.
- A native Swift rewrite would duplicate all business logic for no gain:
  `just_audio` already calls AVFoundation internally, and the hand-crafted
  UI intentionally avoids stock platform chrome.
