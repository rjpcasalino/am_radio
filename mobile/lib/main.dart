import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/player_service.dart';
import 'services/station_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Create PlayerService before runApp so signal handlers can reference it.
  // On Linux without a desktop environment Flutter's dispose() chain is never
  // invoked when the process is killed, so we must stop mpv ourselves here.
  final player = PlayerService();
  final stations = StationRepository();

  // Signal handlers are only meaningful on Linux (where mpv runs as a
  // subprocess).  iOS/Android apps are sandboxed — they don't receive POSIX
  // signals and cannot spawn external processes.
  //
  // SIGINT  — Ctrl+C in a terminal           (conventional exit 130)
  // SIGTERM — sent by systemd / kill / pkill  (conventional exit 143)
  // SIGHUP  — terminal closes / SSH ends      (conventional exit 129)
  if (Platform.isLinux) {
    ProcessSignal.sigint.watch().listen((_) {
      player.stop();
      exit(130); // 128 + SIGINT(2)
    });
    ProcessSignal.sigterm.watch().listen((_) {
      player.stop();
      exit(143); // 128 + SIGTERM(15)
    });
    ProcessSignal.sighup.watch().listen((_) {
      player.stop();
      exit(129); // 128 + SIGHUP(1)
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider.value(value: stations),
      ],
      child: const AmRadioApp(),
    ),
  );

  // Load saved stations asynchronously AFTER runApp to avoid blocking UI.
  // This fixes the ~15s white screen issue on older devices where
  // SharedPreferences I/O would freeze the main thread before the first frame.
  // The UI appears immediately and saved stations populate in the background.
  stations.load().catchError((e) {
    debugPrint('[StationRepository] Failed to load saved stations: $e');
  });
}

class AmRadioApp extends StatelessWidget {
  const AmRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AM Radio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Hand-crafted dark palette that evokes a vintage bakelite transistor radio.
        colorScheme: const ColorScheme.dark(
          surface: Color(0xFF1A0F00),       // dark bakelite body
          primary: Color(0xFFE8A020),       // amber dial backlight
          primaryContainer: Color(0xFF2E1A00),
          onPrimary: Color(0xFF1A0F00),
          onSurface: Color(0xFFF0E0B0),     // cream lettering
          secondary: Color(0xFF4CAF50),     // green ON AIR lamp
          onSecondary: Color(0xFF1A0F00),
          tertiary: Color(0xFFFF6B35),      // warm signal-bar orange
          onTertiary: Color(0xFF1A0F00),
        ),
        scaffoldBackgroundColor: const Color(0xFF1A0F00),
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
