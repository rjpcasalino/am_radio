import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/station.dart';

/// Plays internet radio streams.
///
/// On **Linux** this mirrors what `am_radio.pl` does — mpv handles all the
/// HTTP streaming and audio decoding, so no native audio library is needed.
///
/// On **iOS / Android** [just_audio] is used instead
/// (AVFoundation on iOS, ExoPlayer on Android), because those platforms are
/// sandboxed and cannot spawn external processes.
class PlayerService extends ChangeNotifier {
  // Linux-only: mpv subprocess.
  Process? _process;

  // iOS / Android: just_audio player and its playing-state subscription.
  AudioPlayer? _audioPlayer;
  StreamSubscription<bool>? _playingSub;

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
      if (Platform.isLinux) {
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
      } else {
        // iOS / Android: use just_audio.
        _audioPlayer ??= AudioPlayer();
        await _audioPlayer!.setUrl(station.url);
        await _audioPlayer!.play();

        // Cancel any leftover subscription before attaching to the new stream.
        await _playingSub?.cancel();
        _playingSub = _audioPlayer!.playingStream.listen((isPlaying) {
          if (!isPlaying && _isPlaying) {
            _isPlaying = false;
            notifyListeners();
          }
        });
      }
    } catch (e) {
      _isPlaying = false;
      _currentStation = null;
      notifyListeners();
      rethrow;
    }
  }

  /// Stop the currently playing stream.
  Future<void> stop() async {
    await _playingSub?.cancel();
    _playingSub = null;

    if (_process != null) {
      _process!.kill();
      _process = null;
    }
    await _audioPlayer?.stop();

    _isPlaying = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _process?.kill();
    _audioPlayer?.dispose();
    super.dispose();
  }
}
