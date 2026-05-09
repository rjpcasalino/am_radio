import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:am_radio/screens/log_viewer_screen.dart';
import 'package:am_radio/services/log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LogViewerScreen', () {
    late LogService logService;

    setUp(() {
      logService = LogService();
    });

    testWidgets('should render without crashing', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: logService,
          child: const MaterialApp(
            home: LogViewerScreen(),
          ),
        ),
      );

      expect(find.byType(LogViewerScreen), findsOneWidget);
      expect(find.text('Debug Logs'), findsOneWidget);
    });

    testWidgets('should show "No logs yet" when empty', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: logService,
          child: const MaterialApp(
            home: LogViewerScreen(),
          ),
        ),
      );

      expect(find.text('No logs yet'), findsOneWidget);
    });

    testWidgets('should display log entries', (WidgetTester tester) async {
      logService.log('Test log message', level: LogLevel.info);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: logService,
          child: const MaterialApp(
            home: LogViewerScreen(),
          ),
        ),
      );

      await tester.pump(); // Rebuild after log added

      expect(find.textContaining('Test log message'), findsOneWidget);
      expect(find.text('INFO'), findsOneWidget);
    });

    testWidgets('should show copy and clear buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: logService,
          child: const MaterialApp(
            home: LogViewerScreen(),
          ),
        ),
      );

      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('clear button should clear logs', (WidgetTester tester) async {
      logService.log('Test message');

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: logService,
          child: const MaterialApp(
            home: LogViewerScreen(),
          ),
        ),
      );

      await tester.pump();
      expect(find.textContaining('Test message'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      expect(logService.entries, isEmpty);
    });

    testWidgets('should display different log levels with correct colors',
        (WidgetTester tester) async {
      logService.log('Debug message', level: LogLevel.debug);
      logService.log('Info message', level: LogLevel.info);
      logService.log('Warning message', level: LogLevel.warning);
      logService.log('Error message', level: LogLevel.error);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: logService,
          child: const MaterialApp(
            home: LogViewerScreen(),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('DEBUG'), findsOneWidget);
      expect(find.text('INFO'), findsOneWidget);
      expect(find.text('WARNING'), findsOneWidget);
      expect(find.text('ERROR'), findsOneWidget);
    });
  });

  group('LogService', () {
    test('should add log entries', () {
      final service = LogService();
      service.log('Test message');

      expect(service.entries.length, 1);
      expect(service.entries.first.message, 'Test message');
    });

    test('should limit entries to max', () {
      final service = LogService();

      // Add more than the max (500)
      for (int i = 0; i < 600; i++) {
        service.log('Message $i');
      }

      expect(service.entries.length, 500);
    });

    test('should clear all entries', () {
      final service = LogService();
      service.log('Test 1');
      service.log('Test 2');

      service.clear();

      expect(service.entries, isEmpty);
    });

    test('should export logs as string', () {
      final service = LogService();
      service.log('Message 1', level: LogLevel.info);
      service.log('Message 2', level: LogLevel.error);

      final exported = service.export();

      expect(exported, contains('Message 1'));
      expect(exported, contains('Message 2'));
      expect(exported, contains('[info]'));
      expect(exported, contains('[error]'));
    });
  });
}
