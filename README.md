Requires [`mpv`](https://mpv.io/)

Example:

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

![example](./screenshot.png)

use the `-f` flag to discover stations from [https://de1.api.radio-browser.info/json/stations/search](https://de1.api.radio-browser.info/json/stations/search)

## Mobile App

A Flutter mobile app for Android, iOS, and Linux desktop is available in the `mobile/` directory. See [mobile/README.md](mobile/README.md) for full documentation.

![android](./am_radio_android.png)

### Quick Deploy to Android

Deploy the app to a connected Android device with automatic screenshot capture:

```sh
# From the repo root
./deploy-android.sh

# Or with Nix:
nix run .#deploy-android
```

The script builds the app, installs it on your device, launches it, and captures a screenshot automatically.

???
