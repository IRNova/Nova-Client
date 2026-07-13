import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/nova_theme.dart';

/// An animated radar dish — concentric rings with a rotating gradient sweep and
/// blips for the most recent finds. Echoes NovaRadar's signature visualization,
/// restyled in the Nova design language.
class RadarSweep extends StatefulWidget {
  const RadarSweep({
    super.key,
    required this.active,
    this.blips = const <double>[],
    this.size = 220,
  });

  /// Whether the sweep is spinning (a scan is in progress).
  final bool active;

  /// Normalized blip angles (0..1) to render as detected points.
  final List<double> blips;
  final double size;

  @override
  State<RadarSweep> createState() => _RadarSweepState();
}

class _RadarSweepState extends State<RadarSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(RadarSweep old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _RadarPainter(
            t: _c.value,
            active: widget.active,
            blips: widget.blips,
            cyan: nova.cyan,
            violet: nova.violet,
            grid: nova.border,
            muted: nova.muted,
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.t,
    required this.active,
    required this.blips,
    required this.cyan,
    required this.violet,
    required this.grid,
    required this.muted,
  });

  final double t;
  final bool active;
  final List<double> blips;
  final Color cyan;
  final Color violet;
  final Color grid;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2 - 2;

    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = grid;

    // Concentric rings.
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(c, r * i / 3, gridPaint);
    }
    // Cross hairs.
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), gridPaint);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), gridPaint);

    // Sweep wedge.
    final double angle = t * 2 * math.pi;
    if (active) {
      final Rect rect = Rect.fromCircle(center: c, radius: r);
      final Paint sweep = Paint()
        ..shader = SweepGradient(
          startAngle: angle - 0.9,
          endAngle: angle,
          colors: <Color>[cyan.withValues(alpha: 0.0), cyan.withValues(alpha: 0.35)],
          transform: const GradientRotation(0),
        ).createShader(rect);
      final Path wedge = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(rect, angle - 0.9, 0.9, false)
        ..close();
      canvas.drawPath(wedge, sweep);

      // Leading edge line.
      final Paint edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = cyan.withValues(alpha: 0.8);
      canvas.drawLine(
        c,
        Offset(c.dx + r * math.cos(angle), c.dy + r * math.sin(angle)),
        edge,
      );
    }

    // Blips.
    for (int i = 0; i < blips.length; i++) {
      final double a = blips[i] * 2 * math.pi;
      final double dist = 0.35 + (i % 3) * 0.22;
      final Offset p =
          Offset(c.dx + r * dist * math.cos(a), c.dy + r * dist * math.sin(a));
      final Paint dot = Paint()..color = violet;
      canvas.drawCircle(p, 3.5, dot);
      canvas.drawCircle(
        p,
        7,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = violet.withValues(alpha: 0.5),
      );
    }

    // Center dot.
    canvas.drawCircle(c, 3, Paint()..color = active ? cyan : muted);
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.t != t || old.active != active || old.blips != blips;
}
