# Mobile App Development Plans

The goal is to turn this into a useful mobile application.  We are using
**Flutter** so that one Dart codebase covers both Linux desktop (for NixOS
development) and Android, with iOS possible later.

## Tech stack

| Platform | Status |
|----------|--------|
| Linux desktop (Flutter) | ✅ MVP scaffolded — see `mobile/` |
| Android (Flutter) | 🚧 scaffold ready; audio backend needs work |
| iOS (Flutter) | 🚧 decided — bootstrap pending (needs macOS + Xcode) |

## NixOS / Nix flake

A `flake.nix` lives at the repo root.  Enter the Flutter dev shell with:

```sh
nix develop .#mobile
```

It installs Flutter, cmake, ninja, clang, pkg-config, gtk3, and mpv, and
auto-generates the `linux/` + `android/` platform directories on first entry.

The macOS `shellHook` already exports `DEVELOPER_DIR`.  Once the `ios/`
platform directory is committed (see below), extend the bootstrap line to
include `ios` — but only after confirming `flutter create --platforms ios`
works on your macOS machine.

## Flutter app (`mobile/`)

### Done
- [x] `flake.nix` — `devShells.mobile` with all Linux build deps
- [x] `mobile/pubspec.yaml` — Flutter project metadata (describes Android, iOS, Linux)
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

### Next — iOS bootstrap (requires macOS + Xcode)
- [ ] Run `cd mobile && flutter create . --platforms ios --project-name am_radio`
      and commit the generated `mobile/ios/` directory
- [ ] Run `flutter pub run flutter_launcher_icons` on macOS to populate
      `ios/Runner/Assets.xcassets/` with the app icon (pubspec already has `ios: true`)
- [ ] Extend the `flake.nix` shellHook bootstrap to include `ios` in the platform list
      (only after the above has been verified to work)
- [ ] Verify `flutter build ios --no-codesign` passes in CI (macOS job already added)
- [ ] Test on a physical device or simulator: AVFoundation stream playback,
      ICY metadata display, SharedPreferences persistence

### Next — UI
- [ ] Full transistor radio redesign for the main (radio) view:
      knob widgets (volume, tone), grille texture, curved body, backlit dial window
- [ ] Minimal mode: refine A4-paper print feel (hairline rules between stations,
      bold station name, italic genre, optional serif font)
- [ ] Dark-mode variant of minimal mode (white-on-black terminal aesthetic)

### Next — Features / Platform
- [ ] Android audio backend: verify `just_audio` + ExoPlayer works on device
- [ ] Show live track metadata (ICY tags) in the Now Playing bar
- [ ] Lo-Fi AM filter toggle (pass `--af=…` to mpv on Linux; EQ on mobile)

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
- The only missing piece is the generated `mobile/ios/` Xcode runner
  directory, which `flutter create . --platforms ios` produces in seconds.
