import 'package:flutter_test/flutter_test.dart';
import 'package:am_radio/services/player_service.dart';
import 'package:am_radio/models/station.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerService', () {
    late PlayerService playerService;

    setUp(() {
      playerService = PlayerService();
    });

    tearDown(() {
      playerService.dispose();
    });

    test('initial state should be stopped', () {
      expect(playerService.isPlaying, false);
      expect(playerService.currentStation, null);
      expect(playerService.currentTrack, null);
    });

    test('loFi filter should default to false', () {
      expect(playerService.loFi, false);
    });

    test('setLoFi should update loFi state', () async {
      await playerService.setLoFi(true);
      expect(playerService.loFi, true);

      await playerService.setLoFi(false);
      expect(playerService.loFi, false);
    });

    test('setLoFi with same value should be no-op', () async {
      final initialLoFi = playerService.loFi;
      await playerService.setLoFi(initialLoFi);
      expect(playerService.loFi, initialLoFi);
    });

    test('stop() should be safe when nothing is playing', () async {
      // Should not throw
      await playerService.stop();
      expect(playerService.isPlaying, false);
    });
  });

  group('Station', () {
    test('Station should be created with required fields', () {
      const station = Station(
        name: 'Test Station',
        url: 'https://example.com/stream',
      );

      expect(station.name, 'Test Station');
      expect(station.url, 'https://example.com/stream');
      expect(station.genre, null);
      expect(station.bitrate, null);
    });

    test('Station should be created with optional fields', () {
      const station = Station(
        name: 'Test Station',
        url: 'https://example.com/stream',
        genre: 'Jazz',
        bitrate: 128,
      );

      expect(station.genre, 'Jazz');
      expect(station.bitrate, 128);
    });
  });
}
