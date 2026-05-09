# am_radio

[![License](https://img.shields.io/badge/License-BSD_3--Clause-blue.svg)](https://opensource.org/licenses/BSD-3-Clause)

A command-line and mobile internet radio player with vintage AM radio aesthetics.

**Disclaimer:** Parts of this codebase were developed with assistance from AI tools. All code is original work and is licensed under the BSD 3-Clause License. Me, the human, has read most of it and it seems OK for slop. A nice Big Mac of slop but it runs and works and has bugs that maybe more or less minor and perhaps aesthetic UX stuff only. I have my doubts but the bugs can be prompted away or hand coded away. Use caution and read the code and let me know.

Requires [`mpv`](https://mpv.io/)

## Features

- **CLI Mode**: Terminal-based radio player with optional TUI interface
- **Mobile App**: Flutter app for Android, iOS, and Linux desktop
- **Verbose Logging**: Debug audio drops and stream issues with `-v` flag
- **Performance Mode**: Minimal UI mode for older devices (A4 paper-like design)
- **In-App Debug Logs**: View and export logs directly from the mobile app
- **Station Discovery**: Search radio-browser.info for streams
- **Lo-Fi Filter**: Vintage AM radio audio effect

## Quick Start

### Perl CLI

```bash
# Basic playback
perl am_radio.pl -s 5

# With lo-fi filter and verbose logging
perl am_radio.pl -v -oi -s 5

# TUI mode (vintage radio interface)
perl am_radio.pl -t

# Discover stations
perl am_radio.pl -f "jazz"
```

Example output:
```
perl am_radio.pl -oi -s5
[!] Lo-Fi AM Radio filter activated.

=== Stream Information ===
  Station: Classical KUSC
  Genre:   Classical
  Bitrate: 128 kbps
==========================

Tuning in to KUSC Classical (Los Angeles)...
Press Ctrl+C to stop playback.

=== Now Playing ===
  Track:   Edward Elgar - Enigma Variations Op 36
==========================
```

![CLI screenshot](./screenshot.png)

### Mobile App

See [mobile/README.md](mobile/README.md) for full documentation.

![Android screenshot](./am_radio_android.png)

**Quick Deploy to Android:**
```sh
./deploy-android.sh
# Skip screenshot capture:
./deploy-android.sh --no-screenshot
# Or with Nix:
nix run .#deploy-android
```

## Testing

Run tests to verify functionality:

**Perl tests:**
```bash
cd t && perl 01-basic.t
# Or: prove -v t/
```

**Flutter tests:**
```bash
cd mobile && flutter test
```

See [TESTING.md](TESTING.md) for comprehensive test documentation.

## Debugging

### Startup Performance

The mobile app logs detailed startup timing to help identify performance bottlenecks:
- App initialization time
- runApp() duration
- Settings and station loading times
- Total startup time

View these logs in the in-app debug log viewer (bug icon, top-right).

### Verbose Logging

**Perl:** Use `-v` flag to see mpv lifecycle events, IPC operations, and stream status.

**Flutter:** All PlayerService events are automatically logged. Access logs via the bug icon (🐛) in the app header.

## Performance Mode

For older devices, enable minimal/performance mode:
1. Tap the palette icon (top-left in mobile app)
2. UI switches to flat, paper-like design
3. Removes shadows and GPU-intensive effects
4. Setting persists across restarts

## Implementation Details

This project includes:
- Comprehensive verbose logging for both Perl and Flutter
- Fixed 15-second white-screen startup on older Android devices
- In-app debug log viewer with copy/export functionality
- Performance mode for reduced GPU load
- Full test coverage (Perl + Flutter)

See [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) for technical details.

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.

### Third-Party Dependencies

**Perl CLI (`am_radio.pl`):**
- `mpv` (GPL/LGPL) - Media player, used as external program
- `curl` - For API requests
- `ffprobe` (LGPL) - For stream metadata

**Flutter Mobile App:**
- Flutter SDK (BSD-3-Clause)
- `http` package (BSD-3-Clause)
- `provider` package (MIT)
- `just_audio` package (MIT)
- `shared_preferences` package (BSD-3-Clause)

All dependencies maintain compatible licenses for commercial distribution.
