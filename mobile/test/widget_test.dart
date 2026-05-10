// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:am_radio/main.dart';
import 'package:am_radio/services/player_service.dart';
import 'package:am_radio/services/settings_service.dart';
import 'package:am_radio/services/station_repository.dart';

void main() {
  testWidgets('App renders smoke test', (WidgetTester tester) async {
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
        child: const AmRadioApp(),
      ),
    );

    expect(find.byType(AmRadioApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);

    playerService.dispose();
    stationRepository.dispose();
    settingsService.dispose();
  });
}
