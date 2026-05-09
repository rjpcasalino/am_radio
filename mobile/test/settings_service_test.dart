import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:am_radio/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Mock SharedPreferences for all tests
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsService', () {
    late SettingsService service;

    setUp(() {
      service = SettingsService();
    });

    test('initial minimalMode should be false', () {
      expect(service.minimalMode, false);
    });

    test('load() should read from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'minimal_mode': true});
      final service = SettingsService();

      await service.load();

      expect(service.minimalMode, true);
    });

    test('load() with no saved value should default to false', () async {
      SharedPreferences.setMockInitialValues({});
      final service = SettingsService();

      await service.load();

      expect(service.minimalMode, false);
    });

    test('setMinimalMode() should update value', () async {
      await service.setMinimalMode(true);
      expect(service.minimalMode, true);

      await service.setMinimalMode(false);
      expect(service.minimalMode, false);
    });

    test('setMinimalMode() should persist to SharedPreferences', () async {
      await service.setMinimalMode(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('minimal_mode'), true);
    });

    test('setMinimalMode() with same value should be no-op', () async {
      await service.setMinimalMode(false);
      final initialValue = service.minimalMode;

      await service.setMinimalMode(false);

      expect(service.minimalMode, initialValue);
    });

    test('notifyListeners is called on setMinimalMode', () async {
      var notified = false;
      service.addListener(() {
        notified = true;
      });

      await service.setMinimalMode(true);

      expect(notified, true);
    });
  });
}
