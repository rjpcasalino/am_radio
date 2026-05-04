import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/player_service.dart';

void main() {
  // Create PlayerService before runApp so signal handlers can reference it.
  // On Linux without a desktop environment Flutter's dispose() chain is never
  // invoked when the process is killed, so we must stop mpv ourselves here.
  final player = PlayerService();

  // SIGINT  — Ctrl+C in a terminal           (conventional exit 130)
  // SIGTERM — sent by systemd / kill / pkill  (conventional exit 143)
  // SIGHUP  — terminal closes / SSH ends      (conventional exit 129)
  //
  // player.stop() calls Process.kill() which is synchronous; there is no
  // need for async/await.  The listen() callback is therefore not async so
  // it finishes before exit() is reached.
  //
  // ProcessSignal.sigterm / sighup are not available on Windows; the Platform
  // guard keeps the app portable should a Windows build be added later.
  ProcessSignal.sigint.watch().listen((_) {
    player.stop();
    exit(130); // 128 + SIGINT(2)
  });
  if (!Platform.isWindows) {
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
    ChangeNotifierProvider.value(
      value: player,
      child: const AmRadioApp(),
    ),
  );
}

class AmRadioApp extends StatelessWidget {
  const AmRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AM Radio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8B4513), // saddle-brown — vintage radio
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
