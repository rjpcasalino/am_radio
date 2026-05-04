import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/station.dart';

/// Plays internet radio streams by spawning [mpv] as a child process.
///
/// On Linux this mirrors what `am_radio.pl` does — mpv handles all the
/// HTTP streaming and audio decoding, so no native audio library is needed.
///
/// On Android you will need a different backend (e.g. `audioplayers`).
/// See the README for details.
class PlayerService extends ChangeNotifier {
  Process? _process;
  Station? _currentStation;
  bool _isPlaying = false;

  Station? get currentStation => _currentStation;
  bool get isPlaying => _isPlaying;

  /// Start playing [station].  Stops any currently playing stream first.
  Future<void> play(Station station) async {
    await stop();

    _currentStation = station;
    _isPlaying = true;
    notifyListeners();

    try {
      final process = await Process.start(
        'mpv',
        [
          station.url,
          '--no-video',
          '--really-quiet',
          '--title=${station.name}',
        ],
        // Inherit stderr so mpv error messages surface in the console.
        mode: ProcessStartMode.normal,
      );
      _process = process;

      // React when mpv exits on its own (e.g. stream ends / network error).
      // Capture [process] so stale callbacks from a previous stream don't
      // overwrite state after play() has already been called for a new station.
      process.exitCode.then((_) {
        if (identical(_process, process)) {
          _isPlaying = false;
          _process = null;
          notifyListeners();
        }
      });
    } catch (e) {
      _isPlaying = false;
      _currentStation = null;
      notifyListeners();
      rethrow;
    }
  }

  /// Stop the currently playing stream.
  Future<void> stop() async {
    if (_process != null) {
      _process!.kill();
      _process = null;
    }
    _isPlaying = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _process?.kill();
    super.dispose();
  }
}
