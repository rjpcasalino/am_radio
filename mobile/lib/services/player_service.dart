import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/station.dart';
import 'log_service.dart';

/// Plays internet radio streams.
///
/// On **Linux** this mirrors what `am_radio.pl` does — mpv handles all the
/// HTTP streaming and audio decoding, so no native audio library is needed.
///
/// On **iOS / Android** [just_audio] is used instead
/// (AVFoundation on iOS, ExoPlayer on Android), because those platforms are
/// sandboxed and cannot spawn external processes.
class PlayerService extends ChangeNotifier {
  final LogService? _logService;

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
  bool _loFi = false;

  PlayerService({LogService? logService}) : _logService = logService;

  void _log(String message, {LogLevel level = LogLevel.info}) {
    // Always log to LogService if available
    _logService?.log(message, level: level);

    // Also log to debugPrint for development
    if (kDebugMode) {
      final timestamp = DateTime.now().toIso8601String();
      debugPrint('[$timestamp] [PlayerService] $message');
    }
  }

  Station? get currentStation => _currentStation;
  bool get isPlaying => _isPlaying;
  bool get loFi => _loFi;

  /// True while just_audio is connecting / buffering the stream.
  /// Always false on Linux (mpv doesn't expose buffering state to us).
  bool get isBuffering => _isBuffering;

  /// The current song/track title from ICY stream metadata.
  /// Null when stopped, not yet received, or on Linux (mpv).
  String? get currentTrack => _currentTrack;

  /// Enables or disables the lo-fi AM filter (`highpass=300 Hz,
  /// lowpass=4500 Hz, acompressor`), mirroring the
  /// `--af=lavfi=[…]` flag used by `am_radio.pl`.
  ///
  /// On **Linux** the filter is applied by restarting mpv with the extra
  /// `--af` argument, so the currently playing stream is briefly interrupted.
  /// On **Android/iOS** `just_audio` (ExoPlayer/AVFoundation) does not expose
  /// a matching audio-filter pipeline, so the toggle has no audible effect
  /// on those platforms.
  ///
  /// [value] is the desired lo-fi state; no-op when it matches the current
  /// state.
  Future<void> setLoFi(bool value) async {
    if (_loFi == value) return;
    _loFi = value;
    notifyListeners();
    // Restart playback so the new filter setting takes effect immediately.
    if (_isPlaying && _currentStation != null) {
      await play(_currentStation!);
    }
  }

  /// Start playing [station].  Stops any currently playing stream first.
  Future<void> play(Station station) async {
    _log('play() called for station: ${station.name} (${station.url})');
    await stop();

    _currentStation = station;
    _isPlaying = true;
    notifyListeners();

    try {
      if (Platform.isLinux) {
        _log('Starting mpv subprocess for Linux...');
        final process = await Process.start(
          'mpv',
          [
            station.url,
            '--no-video',
            '--really-quiet',
            '--title=${station.name}',
            if (_loFi)
              '--af=lavfi=[highpass=f=300,lowpass=f=4500,acompressor]',
          ],
          // Inherit stderr so mpv error messages surface in the console.
          mode: ProcessStartMode.normal,
        );
        _process = process;
        _log('mpv started with PID: ${process.pid}');

        // React when mpv exits on its own (e.g. stream ends / network error).
        // Capture [process] so stale callbacks from a previous stream don't
        // overwrite state after play() has already been called for a new station.
        process.exitCode.then((exitCode) {
          if (identical(_process, process)) {
            _log('mpv process exited with code: $exitCode', level: LogLevel.warning);
            _isPlaying = false;
            _process = null;
            notifyListeners();
          }
        });
      } else {
        // iOS / Android: use just_audio.
        _log('Using just_audio for iOS/Android...');
        _audioPlayer ??= AudioPlayer();

        // Mark as buffering while the stream is being set up / connecting.
        _isBuffering = true;
        notifyListeners();
        _log('Buffering started, setting URL...', level: LogLevel.debug);

        await _audioPlayer!.setUrl(station.url);
        _log('URL set, starting playback...');
        await _audioPlayer!.play();
        _log('Playback started successfully');

        // Cancel any leftover subscription before attaching to the new stream.
        await _playingSub?.cancel();
        _playingSub = _audioPlayer!.playingStream.listen((isPlaying) {
          _log('playingStream event: isPlaying=$isPlaying', level: LogLevel.debug);
          if (!isPlaying && _isPlaying) {
            _log('Stream stopped unexpectedly (possible audio drop)', level: LogLevel.warning);
            _isPlaying = false;
            _isBuffering = false;
            notifyListeners();
          }
        });

        // Track processing state so the UI can distinguish
        // buffering/connecting from actively streaming audio.
        await _processingSub?.cancel();
        _processingSub = _audioPlayer!.processingStateStream.listen((state) {
          _log('processingStateStream event: $state', level: LogLevel.debug);
          final buffering = state == ProcessingState.loading ||
              state == ProcessingState.buffering;
          if (buffering != _isBuffering) {
            _isBuffering = buffering;
            _log('Buffering state changed: $_isBuffering');
            notifyListeners();
          }
        });

        // Receive ICY stream metadata (current song title) as it arrives.
        await _icySub?.cancel();
        _icySub = _audioPlayer!.icyMetadataStream.listen((meta) {
          final title = meta?.info?.title;
          if (title != _currentTrack) {
            _log('Track changed: $title');
            _currentTrack = title;
            notifyListeners();
          }
        });
      }
    } catch (e) {
      _log('ERROR in play(): $e', level: LogLevel.error);
      _isPlaying = false;
      _currentStation = null;
      notifyListeners();
      rethrow;
    }
  }

  /// Stop the currently playing stream.
  Future<void> stop() async {
    if (!_isPlaying && _process == null && _audioPlayer == null) {
      _log('stop() called but nothing is playing', level: LogLevel.debug);
      return;
    }
    _log('stop() called');
    try {
      await _playingSub?.cancel();
      _playingSub = null;
      await _processingSub?.cancel();
      _processingSub = null;
      await _icySub?.cancel();
      _icySub = null;

      if (_process != null) {
        _log('Killing mpv process PID: ${_process!.pid}');
        _process!.kill();
        _process = null;
      }
      if (_audioPlayer != null) {
        _log('Stopping just_audio player');
        await _audioPlayer?.stop();
      }
      _log('Playback stopped successfully');
    } finally {
      _isPlaying = false;
      _isBuffering = false;
      _currentTrack = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _log('dispose() called - cleaning up resources', level: LogLevel.debug);
    _playingSub?.cancel();
    _processingSub?.cancel();
    _icySub?.cancel();
    _process?.kill();
    _audioPlayer?.dispose();
    super.dispose();
  }
}
