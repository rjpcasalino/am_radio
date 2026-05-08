import 'package:flutter/material.dart';

/// Converts a station [idx] (0-based, out of [total]) into a fake AM-band
/// frequency label — identical logic to `tui_fake_freq` in `am_radio.pl`.
///
/// Maps the station list evenly across 540–1700 kHz and rounds to the
/// nearest 10 kHz channel for that vintage AM feel.
int fakeFreqKHz(int idx, int total) {
  if (total <= 1) return 1020;
  final f = 540 + (idx * (1700 - 540) / (total - 1)).round();
  return ((f + 5) ~/ 10) * 10;
}

/// Horizontal AM-band frequency dial.
///
/// Shows a ━━━ line with a ▼ needle positioned over the active station,
/// with tick marks and truncated station names below the line.
///
/// * **Tap** a tick region to jump to that station.
/// * **Swipe** left/right to step to the next/previous station.
///
/// Mirrors the ◀ ▶ tune and 1–9 preset navigation from the TUI.
class FrequencyDial extends StatelessWidget {
  final int stationCount;
  final int currentIndex;
  final List<String> stationNames;
  final ValueChanged<int> onStationChanged;

  const FrequencyDial({
    super.key,
    required this.stationCount,
    required this.currentIndex,
    required this.stationNames,
    required this.onStationChanged,
  });

  int? _hitTest(double x, double totalWidth) {
    if (stationCount == 0) return null;
    if (stationCount == 1) return 0;
    const margin = 24.0;
    final dialW = totalWidth - margin * 2;
    for (int i = 0; i < stationCount; i++) {
      final sx = margin + i * dialW / (stationCount - 1);
      if ((x - sx).abs() < 22) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final totalWidth = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final idx = _hitTest(d.localPosition.dx, totalWidth);
            if (idx != null) onStationChanged(idx);
          },
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -100 && currentIndex < stationCount - 1) {
              onStationChanged(currentIndex + 1);
            } else if (v > 100 && currentIndex > 0) {
              onStationChanged(currentIndex - 1);
            }
          },
          child: CustomPaint(
            size: Size(totalWidth, 90),
            painter: _DialPainter(
              stationCount: stationCount,
              currentIndex: currentIndex,
              stationNames: stationNames,
            ),
          ),
        );
      },
    );
  }
}

class _DialPainter extends CustomPainter {
  final int stationCount;
  final int currentIndex;
  final List<String> stationNames;

  const _DialPainter({
    required this.stationCount,
    required this.currentIndex,
    required this.stationNames,
  });

  static const _kMargin = 24.0;
  static const _kLineY = 44.0;
  static const _kAmber = Color(0xFFE8A020);
  static const _kDim = Color(0xFF4A2800);

  double _stationX(int i, double totalWidth) {
    if (stationCount <= 1) return totalWidth / 2;
    return _kMargin + i * (totalWidth - _kMargin * 2) / (stationCount - 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ── Dial line ──────────────────────────────────────────────────────────
    canvas.drawLine(
      const Offset(_kMargin, _kLineY),
      Offset(size.width - _kMargin, _kLineY),
      Paint()
        ..color = _kAmber
        ..strokeWidth = 1.5,
    );

    // ── Ticks and station name labels ──────────────────────────────────────
    for (int i = 0; i < stationCount; i++) {
      final x = _stationX(i, size.width);
      final active = i == currentIndex;

      canvas.drawLine(
        Offset(x, _kLineY - 6),
        Offset(x, _kLineY + 6),
        Paint()
          ..color = active ? _kAmber : _kDim
          ..strokeWidth = active ? 2 : 1,
      );

      final label = _truncate(stationNames[i], 9);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: active ? _kAmber : _kDim,
            fontSize: 8.5,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, _kLineY + 10));
    }

    // ── Needle (▼ triangle) and frequency label above active station ───────
    if (stationCount > 0) {
      final nx = _stationX(currentIndex, size.width);

      // Triangle pointer
      final path = Path()
        ..moveTo(nx - 5, _kLineY - 18)
        ..lineTo(nx + 5, _kLineY - 18)
        ..lineTo(nx, _kLineY - 8)
        ..close();
      canvas.drawPath(path, Paint()..color = _kAmber);

      // Frequency label above the triangle
      final freq = fakeFreqKHz(currentIndex, stationCount);
      final freqTp = TextPainter(
        text: TextSpan(
          text: '$freq',
          style: const TextStyle(
            color: _kAmber,
            fontSize: 9,
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      freqTp.paint(
        canvas,
        Offset(
          (nx - freqTp.width / 2)
              .clamp(_kMargin, size.width - _kMargin - freqTp.width),
          _kLineY - 34,
        ),
      );
    }

    // ── "kHz" label at the right end of the line ───────────────────────────
    final kHzTp = TextPainter(
      text: const TextSpan(
        text: 'kHz',
        style: TextStyle(
          color: _kDim,
          fontSize: 8,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    kHzTp.paint(
      canvas,
      Offset(size.width - _kMargin + 3, _kLineY - 4),
    );
  }

  String _truncate(String s, int maxChars) {
    if (s.length <= maxChars) return s;
    return '${s.substring(0, maxChars - 1)}…';
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.stationCount != stationCount ||
      old.currentIndex != currentIndex ||
      old.stationNames != stationNames;
}
