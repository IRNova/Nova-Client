import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/proxy/proxy_controller.dart';
import '../theme/nova_gradients.dart';
import '../theme/nova_semantics.dart';
import '../theme/nova_theme.dart';
import 'nova_logo.dart';

/// The signature connect control: a glowing ring around the Nova mark, colored
/// by the live connection state (cyan→violet idle, green connected, amber
/// busy). The ring sweep rotates continuously only while connecting/
/// disconnecting; otherwise it sits still and the glow gently breathes.
///
/// A faithful Dart port of the native `NovaConnectOrb`. In [showLabel] mode it
/// stacks a top status line + logo + bottom label; otherwise it is a clean
/// logo-only orb (the home hero uses this at 168dp).
class NovaConnectOrb extends StatefulWidget {
  const NovaConnectOrb({
    super.key,
    required this.state,
    this.onTap,
    this.size = 232,
    this.showLabel = false,
    this.label,
    this.statusText,
  });

  final ProxyConnectionState state;
  final VoidCallback? onTap;
  final double size;
  final bool showLabel;
  final String? label;
  final String? statusText;

  @override
  State<NovaConnectOrb> createState() => _NovaConnectOrbState();
}

class _NovaConnectOrbState extends State<NovaConnectOrb>
    with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(NovaConnectOrb old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _syncSpin();
  }

  void _syncSpin() {
    if (widget.state.isBusy) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final visual = NovaConnectVisual.of(widget.state, nova);
    final bool connected = widget.state.isActive;

    return Semantics(
      button: true,
      label: widget.statusText ?? widget.label,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[_spin, _pulse]),
            builder: (context, _) {
              return CustomPaint(
                painter: _OrbPainter(
                  accent: visual.accent,
                  connected: connected,
                  busy: widget.state.isBusy,
                  spin: _spin.value,
                  pulse: _pulse.value,
                ),
                child: Center(
                  child: widget.showLabel
                      ? _LabeledContent(
                          state: widget.state,
                          accent: visual.accent,
                          size: widget.size,
                          label: widget.label,
                          statusText: widget.statusText,
                        )
                      : NovaLogo(size: widget.size * 0.56),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LabeledContent extends StatelessWidget {
  const _LabeledContent({
    required this.state,
    required this.accent,
    required this.size,
    this.label,
    this.statusText,
  });

  final ProxyConnectionState state;
  final Color accent;
  final double size;
  final String? label;
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (statusText != null)
          Text(statusText!,
              style: text.labelSmall?.copyWith(color: accent)),
        SizedBox(height: size * 0.04),
        NovaLogo(size: size * 0.30),
        SizedBox(height: size * 0.04),
        if (label != null)
          Text(label!,
              style: text.titleSmall
                  ?.copyWith(color: accent, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.accent,
    required this.connected,
    required this.busy,
    required this.spin,
    required this.pulse,
  });

  final Color accent;
  final bool connected;
  final bool busy;
  final double spin; // 0..1 continuous while busy
  final double pulse; // 0..1 breathing

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2;

    final double strokeW = size.shortestSide * 0.05;
    // The sweep ring sits near the outer edge so the dark disc it encloses is
    // large enough to hold the Nova mark without the logo spilling past it.
    final double ringR = r - strokeW * 0.8;

    // 1) Radial glow, sized to the ring. Kept deliberately restrained (an
    // enterprise look, not a gamer neon): a soft presence, not a spotlight.
    final double glowAlpha = busy
        ? 0.14 + 0.10 * pulse
        : connected
            ? 0.20
            : 0.10;
    final Paint glow = Paint()
      ..shader = RadialGradient(
        colors: <Color>[
          accent.withValues(alpha: glowAlpha),
          accent.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: ringR));
    canvas.drawCircle(c, ringR, glow);

    // 2) Sweep ring stroke.
    final List<Color> sweep =
        connected ? NovaGradients.orbSweepConnected : NovaGradients.orbSweepIdle;
    final double rot = busy ? spin * 2 * math.pi : -math.pi / 2;
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        // Idle uses the cyan→violet sweep too (matching the native orb), not a
        // flat single-accent ring.
        colors: connected || busy ? sweep : NovaGradients.orbSweepIdle,
        transform: GradientRotation(rot),
      ).createShader(Rect.fromCircle(center: c, radius: ringR));
    canvas.drawCircle(c, ringR, ring);

    // 3) Inner dark screen disc filling the ring.
    final Paint disc = Paint()..color = const Color(0xFF0A0C12);
    canvas.drawCircle(c, ringR - strokeW * 0.6, disc);
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.accent != accent ||
      old.connected != connected ||
      old.busy != busy ||
      old.spin != spin ||
      old.pulse != pulse;
}
