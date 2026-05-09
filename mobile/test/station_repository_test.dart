import 'package:flutter_test/flutter_test.dart';
import 'package:am_radio/services/station_repository.dart';
import 'package:am_radio/models/station.dart';

void main() {
  group('StationRepository', () {
    late StationRepository repository;

    setUp(() {
      repository = StationRepository();
    });

    test('initial saved list should be empty', () {
      expect(repository.saved, isEmpty);
    });

    test('save() should add station to saved list', () async {
      const station = Station(
        name: 'Test Station',
        url: 'https://example.com/stream',
      );

      await repository.save(station);
      expect(repository.saved.length, 1);
      expect(repository.saved.first.name, 'Test Station');
    });

    test('save() should not add duplicate stations', () async {
      const station = Station(
        name: 'Test Station',
        url: 'https://example.com/stream',
      );

      await repository.save(station);
      await repository.save(station);
      expect(repository.saved.length, 1);
    });

    test('isSaved() should return true for saved stations', () async {
      const station = Station(
        name: 'Test Station',
        url: 'https://example.com/stream',
      );

      expect(repository.isSaved(station), false);
      await repository.save(station);
      expect(repository.isSaved(station), true);
    });

    test('remove() should remove station from saved list', () async {
      const station = Station(
        name: 'Test Station',
        url: 'https://example.com/stream',
      );

      await repository.save(station);
      expect(repository.saved.length, 1);

      await repository.remove(station);
      expect(repository.saved, isEmpty);
    });

    test('remove() should be no-op for non-saved stations', () async {
      const station = Station(
        name: 'Test Station',
        url: 'https://example.com/stream',
      );

      await repository.remove(station);
      expect(repository.saved, isEmpty);
    });
  });
}
