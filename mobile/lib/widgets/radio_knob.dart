import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A vintage bakelite rotary knob, painted with [CustomPainter].
///
/// [indicatorAngle] controls where the grip-line pointer aims:
///   0.0      = 12 o'clock (top)
///   π/2      = 3 o'clock  (right)
///   π / -π   = 6 o'clock  (bottom)
///   -π/2     = 9 o'clock  (left)
///
/// The knob briefly scales down when pressed to mimic a physical click.
class RadioKnob extends StatefulWidget {
  final String label;
  final double size;
  final bool enabled;

  /// When true the knob glows amber (e.g. playback active, filter on).
  final bool isActive;

  /// Where the indicator pointer aims (see class doc for convention).
  final double indicatorAngle;

  /// Fired on a simple tap (if [enabled]).
  final VoidCallback? onTap;

  const RadioKnob({
    super.key,
    required this.label,
    this.size = 56,
    this.enabled = true,
    this.isActive = false,
    this.indicatorAngle = 0,
    this.onTap,
  });

  @override
  State<RadioKnob> createState() => _RadioKnobState();
}

class _RadioKnobState extends State<RadioKnob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 70),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => _press.reverse() : null,
      onTapUp: widget.enabled
          ? (_) {
              _press.forward();
              widget.onTap?.call();
            }
          : null,
      onTapCancel: () => _press.forward(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _press,
            builder: (_, child) =>
                Transform.scale(scale: _press.value, child: child),
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _KnobPainter(
                enabled: widget.enabled,
                isActive: widget.isActive,
                indicatorAngle: widget.indicatorAngle,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              letterSpacing: 1.2,
              color: widget.enabled
                  ? const Color(0xFFF0E0B0)
                  : const Color(0xFF4A2800),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Custom painter ─────────────────────────────────────────────────────────

class _KnobPainter extends CustomPainter {
  final bool enabled;
  final bool isActive;
  final double indicatorAngle;

  const _KnobPainter({
    required this.enabled,
    required this.isActive,
    required this.indicatorAngle,
  });

  static const _amber = Color(0xFFE8A020);
  static const _dimAmber = Color(0xFF4A2800);
  static const _rim = Color(0xFF2E1A00);
  static const _face = Color(0xFF120A00);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = math.min(cx, cy) - 1.5;

    final activeColor = enabled ? _amber : _dimAmber;

    // Glow when active
    if (isActive && enabled) {
      canvas.drawCircle(
        Offset(cx, cy),
        r + 6,
        Paint()
          ..color = _amber.withOpacity(0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    // Outer ring body
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = _rim);

    // Outer ring border
    canvas.drawCircle(
      Offset(cx, cy),
      r,
      Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Scale tick marks at the rim
    final tickPaint = Paint()
      ..color = activeColor.withOpacity(0.45)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 12; i++) {
      final a = i * math.pi / 6 - math.pi / 2;
      canvas.drawLine(
        Offset(cx + (r - 5) * math.cos(a), cy + (r - 5) * math.sin(a)),
        Offset(cx + (r - 1) * math.cos(a), cy + (r - 1) * math.sin(a)),
        tickPaint,
      );
    }

    // Inner knob face
    final ir = r - 7;
    canvas.drawCircle(Offset(cx, cy), ir, Paint()..color = _face);

    // Knurling — fine radial lines near the face edge
    final knurlPaint = Paint()
      ..color = activeColor.withOpacity(0.2)
      ..strokeWidth = 0.8;
    for (int i = 0; i < 20; i++) {
      final a = i * math.pi / 10;
      canvas.drawLine(
        Offset(cx + (ir - 3.5) * math.cos(a), cy + (ir - 3.5) * math.sin(a)),
        Offset(cx + (ir - 0.5) * math.cos(a), cy + (ir - 0.5) * math.sin(a)),
        knurlPaint,
      );
    }

    // Indicator: line from centre to near edge, capped with a filled dot.
    // indicatorAngle 0 = 12 o'clock → subtract π/2 for standard math coords.
    final a = indicatorAngle - math.pi / 2;
    final lineEnd = ir - 7;
    final dotPos = Offset(cx + lineEnd * math.cos(a), cy + lineEnd * math.sin(a));

    canvas.drawLine(
      Offset(cx, cy),
      dotPos,
      Paint()
        ..color = activeColor.withOpacity(0.7)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(dotPos, 3.5, Paint()..color = activeColor);
  }

  @override
  bool shouldRepaint(_KnobPainter old) =>
      old.enabled != enabled ||
      old.isActive != isActive ||
      old.indicatorAngle != indicatorAngle;
}
