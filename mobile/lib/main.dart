import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/player_service.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => PlayerService(),
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
