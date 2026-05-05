import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Animated signal-strength meter — 10 small bars that flicker while playing.
///
/// When [isPlaying] is true the lit-bar count drifts ±1 every 300 ms,
/// mimicking the signal meter in the TUI (`▰▰▰▰▰▰▰▱▱▱`).
/// When stopped all bars are rendered dim.
class SignalMeter extends StatefulWidget {
  final bool isPlaying;

  const SignalMeter({super.key, required this.isPlaying});

  @override
  State<SignalMeter> createState() => _SignalMeterState();
}

class _SignalMeterState extends State<SignalMeter> {
  static const _kBars = 10;
  static const _kInitLit = 7;

  // Initialised to 0 so bars are dark before any playback begins.
  int _litBars = 0;
  Timer? _timer;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _startMeter();
  }

  @override
  void didUpdateWidget(SignalMeter old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying == old.isPlaying) return;
    if (widget.isPlaying) {
      _startMeter();
    } else {
      _stopMeter();
    }
  }

  void _startMeter() {
    _timer?.cancel();
    _litBars = _kInitLit;
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted) return;
      setState(() {
        _litBars = (_litBars + _rng.nextInt(3) - 1).clamp(4, _kBars);
      });
    });
  }

  void _stopMeter() {
    _timer?.cancel();
    _timer = null;
    setState(() => _litBars = 0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        _kBars,
        (i) => Container(
          width: 5,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: i < _litBars
                ? const Color(0xFFFF6B35)
                : const Color(0xFF3D1800),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}
