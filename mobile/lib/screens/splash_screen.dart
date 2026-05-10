import 'package:flutter/material.dart';

import 'home_screen.dart';

/// Animated intro screen shown once at app start.
///
/// "AM_" slides in from the left while "RADIO" slides in from the right.
/// They meet in the centre to form "AM_RADIO", hold briefly, then the screen
/// fades into [HomeScreen].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _leftSlide;
  late final Animation<Offset> _rightSlide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _leftSlide = Tween<Offset>(
      begin: const Offset(-2.0, 0),
      end: Offset.zero,
    ).animate(curved);

    _rightSlide = Tween<Offset>(
      begin: const Offset(2.0, 0),
      end: Offset.zero,
    ).animate(curved);

    // Slide in, hold for a moment, then navigate.
    _controller.forward().then((_) {
      if (!mounted) return;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0F00),
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SlideTransition(
              position: _leftSlide,
              child: const Text(
                'AM_',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: Color(0xFFF0E0B0), // cream — readable on dark bakelite
                ),
              ),
            ),
            SlideTransition(
              position: _rightSlide,
              child: const Text(
                'RADIO',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: Color(0xFFF0E0B0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
