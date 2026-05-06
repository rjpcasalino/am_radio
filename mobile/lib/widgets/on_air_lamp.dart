import 'package:flutter/material.dart';

/// Pulsing "● ON AIR" indicator — green when on, dim when off.
///
/// Mirrors the `$st->{pulse}` beat from the TUI: opacity oscillates between
/// 0.3 and 1.0 with an 800 ms cycle while [isOn] is true.
class OnAirLamp extends StatefulWidget {
  final bool isOn;

  const OnAirLamp({super.key, required this.isOn});

  @override
  State<OnAirLamp> createState() => _OnAirLampState();
}

class _OnAirLampState extends State<OnAirLamp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.isOn) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(OnAirLamp old) {
    super.didUpdateWidget(old);
    if (widget.isOn && !old.isOn) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.isOn && old.isOn) {
      _ctrl.stop();
      _ctrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: widget.isOn ? _opacity.value : 0.25,
        child: const Text(
          '● ON AIR',
          style: TextStyle(
            color: Color(0xFF4CAF50),
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            fontSize: 11,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
