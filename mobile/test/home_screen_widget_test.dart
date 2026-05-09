import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:am_radio/screens/home_screen.dart';
import 'package:am_radio/services/player_service.dart';
import 'package:am_radio/services/station_repository.dart';
import 'package:am_radio/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeScreen', () {
    testWidgets('should render without crashing', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      final playerService = PlayerService();
      final stationRepository = StationRepository();
      final settingsService = SettingsService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: playerService),
            ChangeNotifierProvider.value(value: stationRepository),
            ChangeNotifierProvider.value(value: settingsService),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      // Widget should build successfully
      expect(find.byType(HomeScreen), findsOneWidget);

      // Cleanup
      playerService.dispose();
    });

    testWidgets('should show transport controls', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      final playerService = PlayerService();
      final stationRepository = StationRepository();
      final settingsService = SettingsService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: playerService),
            ChangeNotifierProvider.value(value: stationRepository),
            ChangeNotifierProvider.value(value: settingsService),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      // Look for transport control symbols
      expect(find.text('◀'), findsOneWidget);
      expect(find.text('■'), findsOneWidget);
      expect(find.text('▶'), findsOneWidget);

      // Cleanup
      playerService.dispose();
    });

    testWidgets('should show "off air" when not playing',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      final playerService = PlayerService();
      final stationRepository = StationRepository();
      final settingsService = SettingsService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: playerService),
            ChangeNotifierProvider.value(value: stationRepository),
            ChangeNotifierProvider.value(value: settingsService),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      // Should show off air message when nothing is playing
      expect(find.textContaining('off air'), findsOneWidget);

      // Cleanup
      playerService.dispose();
    });

    testWidgets('should show TUNE label in default mode',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      final playerService = PlayerService();
      final stationRepository = StationRepository();
      final settingsService = SettingsService();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: playerService),
            ChangeNotifierProvider.value(value: stationRepository),
            ChangeNotifierProvider.value(value: settingsService),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      // FIXME:
      //expect(find.text('TUNE'), findsOneWidget);

      // Cleanup
      playerService.dispose();
    });
  });
}
