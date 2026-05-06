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
  StreamSubscription<ProcessingState>? _processingSub;
  StreamSubscription<IcyMetadata?>? _icySub;

  Station? _currentStation;
  bool _isPlaying = false;
  bool _isBuffering = false;
  String? _currentTrack;

  Station? get currentStation => _currentStation;
  bool get isPlaying => _isPlaying;

  /// True while just_audio is connecting / buffering the stream.
  /// Always false on Linux (mpv doesn't expose buffering state to us).
  bool get isBuffering => _isBuffering;

  /// The current song/track title from ICY stream metadata.
  /// Null when stopped, not yet received, or on Linux (mpv).
  String? get currentTrack => _currentTrack;

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

        // Mark as buffering while the stream is being set up / connecting.
        _isBuffering = true;
        notifyListeners();

        await _audioPlayer!.setUrl(station.url);
        await _audioPlayer!.play();

        // Cancel any leftover subscription before attaching to the new stream.
        await _playingSub?.cancel();
        _playingSub = _audioPlayer!.playingStream.listen((isPlaying) {
          if (!isPlaying && _isPlaying) {
            _isPlaying = false;
            _isBuffering = false;
            notifyListeners();
          }
        });

        // Track processing state so the UI can distinguish
        // buffering/connecting from actively streaming audio.
        await _processingSub?.cancel();
        _processingSub = _audioPlayer!.processingStateStream.listen((state) {
          final buffering = state == ProcessingState.loading ||
              state == ProcessingState.buffering;
          if (buffering != _isBuffering) {
            _isBuffering = buffering;
            notifyListeners();
          }
        });

        // Receive ICY stream metadata (current song title) as it arrives.
        await _icySub?.cancel();
        _icySub = _audioPlayer!.icyMetadataStream.listen((meta) {
          final title = meta?.info?.title;
          if (title != _currentTrack) {
            _currentTrack = title;
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
    await _processingSub?.cancel();
    _processingSub = null;
    await _icySub?.cancel();
    _icySub = null;

    if (_process != null) {
      _process!.kill();
      _process = null;
    }
    await _audioPlayer?.stop();

    _isPlaying = false;
    _isBuffering = false;
    _currentTrack = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _processingSub?.cancel();
    _icySub?.cancel();
    _process?.kill();
    _audioPlayer?.dispose();
    super.dispose();
  }
}
