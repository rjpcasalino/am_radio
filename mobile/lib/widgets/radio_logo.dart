import 'package:flutter/material.dart';

/// A compact transistor-radio logo painted purely in code.
///
/// Draws a bakelite body with a speaker-grille dot pattern on the left,
/// an amber dial window with a needle on the right, and "AM RADIO" brand
/// text centred in the window.  Used in the app header strip.
class RadioLogo extends StatelessWidget {
  /// Overall width; height is always [width] × 0.5.
  final double width;

  const RadioLogo({super.key, this.width = 100});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, width * 0.5),
      painter: const _RadioLogoPainter(),
      child: SizedBox(width: width, height: width * 0.5),
    );
  }
}

class _RadioLogoPainter extends CustomPainter {
  const _RadioLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Bakelite body ──────────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, h),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFF2E1A00),
    );

    // ── Speaker grille — dot grid on left ~40 % ────────────────────────────
    final grillRight = w * 0.38;
    final dotPaint = Paint()..color = const Color(0xFF5C3800);
    const dotSpacing = 4.5;
    const dotR = 1.2;
    for (double dy = 5; dy < h - 3; dy += dotSpacing) {
      for (double dx = 5; dx < grillRight - 2; dx += dotSpacing) {
        canvas.drawCircle(Offset(dx, dy), dotR, dotPaint);
      }
    }

    // Thin vertical separator between grille and dial
    canvas.drawLine(
      Offset(grillRight + 2, 4),
      Offset(grillRight + 2, h - 4),
      Paint()
        ..color = const Color(0xFF4A2800)
        ..strokeWidth = 1,
    );

    // ── Dial window ────────────────────────────────────────────────────────
    final dialLeft = grillRight + 5;
    final dialRect = Rect.fromLTWH(dialLeft, 4, w - dialLeft - 4, h - 8);
    final dialRRect =
        RRect.fromRectAndRadius(dialRect, const Radius.circular(3));

    // Gradient fill
    canvas.drawRRect(
      dialRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF1A0F00), Color(0xFF0A0500)],
        ).createShader(dialRect),
    );

    // Amber border
    canvas.drawRRect(
      dialRRect,
      Paint()
        ..color = const Color(0xFFE8A020)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Needle line
    final needleX = dialLeft + (w - dialLeft - 4) * 0.55;
    canvas.drawLine(
      Offset(needleX, 6),
      Offset(needleX, h - 6),
      Paint()
        ..color = const Color(0xFFE8A020)
        ..strokeWidth = 1.2,
    );

    // ── "AM RADIO" brand text centred in the dial window ──────────────────
    final tp = TextPainter(
      text: const TextSpan(
        text: 'AM RADIO',
        style: TextStyle(
          color: Color(0xFFE8A020),
          fontSize: 8,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tx = dialLeft + ((w - dialLeft - 4) - tp.width) / 2;
    final ty = (h - tp.height) / 2;
    tp.paint(canvas, Offset(tx, ty));
  }

  @override
  bool shouldRepaint(_RadioLogoPainter old) => false;
}
