import 'package:flutter/material.dart';

import '../core/proxy/conn_info_controller.dart';
import '../theme/nova_semantics.dart';
import '../theme/nova_theme.dart';

/// A rounded, tinted icon chip — the small colored square holding an icon used
/// across the Nova cards (metrics, tools, config card, server rows).
class NovaIconChip extends StatelessWidget {
  const NovaIconChip({
    super.key,
    required this.icon,
    required this.color,
    this.size = 38,
    this.radius = 11,
    this.iconScale = 0.5,
  });

  final IconData icon;
  final Color color;
  final double size;
  final double radius;
  final double iconScale;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: size * iconScale),
    );
  }
}

/// A country flag emoji (from an ISO-2 code), falling back to a globe icon when
/// the code is missing or unknown. Mirrors the native `NovaCountryFlag`.
class NovaCountryFlag extends StatelessWidget {
  const NovaCountryFlag({super.key, required this.iso2, this.size = 18});

  final String? iso2;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? flag = countryFlagEmoji(iso2);
    if (flag == null) {
      return Icon(Icons.public, size: size, color: context.nova.muted);
    }
    return Text(flag, style: TextStyle(fontSize: size));
  }
}

/// Four ascending signal bars, lit according to latency (lower = more bars),
/// matching the native server-row `SignalBars`.
class NovaSignalBars extends StatelessWidget {
  const NovaSignalBars({super.key, required this.latencyMs, this.color});

  final int? latencyMs;
  final Color? color;

  int get _lit {
    final int? ms = latencyMs;
    if (ms == null) return 0;
    if (ms < 120) return 4;
    if (ms < 200) return 3;
    if (ms < 350) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final Color on = color ?? NovaSemantics.ping(latencyMs);
    final Color off = context.nova.borderStrong;
    const List<double> heights = <double>[5, 8, 11, 14];
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        for (int i = 0; i < 4; i++) ...<Widget>[
          Container(
            width: 3,
            height: heights[i],
            decoration: BoxDecoration(
              color: i < _lit ? on : off,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (i < 3) const SizedBox(width: 2),
        ],
      ],
    );
  }
}

/// The "Connected / Not connected" status pill — a colored dot + label on a
/// translucent tint of the status color. Mirrors `NovaStatusBadge`.
class NovaStatusBadge extends StatelessWidget {
  const NovaStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

/// A small protocol badge (e.g. "VLESS") — uppercase accent text on a faint
/// surface pill, matching the native `ProtocolBadge`.
class NovaProtocolBadge extends StatelessWidget {
  const NovaProtocolBadge({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? NovaSemantics.successGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: c,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0.4,
            ),
      ),
    );
  }
}
