# Mobile App Development Plans

The goal is to turn this into a useful mobile application.  We are using
**Flutter** so that one Dart codebase covers both Linux desktop (for NixOS
development) and Android, with iOS possible later.

## Tech stack

| Platform | Status |
|----------|--------|
| Linux desktop (Flutter) | ✅ MVP scaffolded — see `mobile/` |
| Android (Flutter) | 🚧 scaffold ready; audio backend needs work |
| iOS (Swift) | 🔜 not started |

## NixOS / Nix flake

A `flake.nix` lives at the repo root.  Enter the Flutter dev shell with:

```sh
nix develop .#mobile
```

It installs Flutter, cmake, ninja, clang, pkg-config, gtk3, and mpv, and
auto-generates the `linux/` + `android/` platform directories on first entry.

## Flutter app (`mobile/`)

### Done
- [x] `flake.nix` — `devShells.mobile` with all Linux build deps
- [x] `mobile/pubspec.yaml` — Flutter project metadata
- [x] `mobile/lib/main.dart` — app entry + dark Material 3 theme (vintage bakelite)
- [x] `mobile/lib/models/station.dart` — Station data class (config + JSON)
- [x] `mobile/lib/services/player_service.dart` — mpv subprocess player (Linux) + just_audio (Android/iOS)
- [x] `mobile/lib/screens/home_screen.dart` — station list + radio-browser search
- [x] `mobile/lib/widgets/frequency_dial.dart` — horizontal AM-band dial (tap/swipe to tune)
- [x] `mobile/lib/widgets/radio_logo.dart` — hand-drawn transistor radio logo (header)
- [x] `mobile/lib/widgets/signal_meter.dart` — animated signal-strength bar meter
- [x] `mobile/lib/services/station_repository.dart` — persist saved stations via SharedPreferences
- [x] `mobile/lib/services/settings_service.dart` — persist settings (minimal mode, list/radio view)
- [x] Minimal (A4-paper) mode: white background, black text, no logo — toggle from header
- [x] List / radio view toggle: "list" = simple station list; "radio" = frequency dial + list
- [x] `FrequencyDial` widget wired into radio (dial) view — tap tick or swipe to change station
- [x] `.github/workflows/flutter.yml` — CI: `flutter analyze` + `flutter test` on every PR

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

## iOS (future)
- [ ] Decide: Swift native vs Flutter (add `--platforms ios` to flutter create)
- [ ] Set up Xcode project
