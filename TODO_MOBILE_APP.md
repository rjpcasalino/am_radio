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
- [x] `mobile/lib/main.dart` — app entry + dark Material 3 theme
- [x] `mobile/lib/models/station.dart` — Station data class (config + JSON)
- [x] `mobile/lib/services/player_service.dart` — mpv subprocess player
- [x] `mobile/lib/screens/home_screen.dart` — station list + radio-browser search

### Next
- [ ] Android audio backend (replace mpv subprocess with `audioplayers`)
- [ ] Persist custom stations to a local file
- [ ] Show live track metadata (ICY tags) in the Now Playing bar
- [ ] Lo-Fi AM filter toggle (pass `--af=…` to mpv on Linux)
- [ ] Android `AndroidManifest.xml` INTERNET permission (auto-added by flutter create)
- [ ] CI: `flutter analyze` + `flutter test`

## iOS (future)
- [ ] Decide: Swift native vs Flutter (add `--platforms ios` to flutter create)
- [ ] Set up Xcode project