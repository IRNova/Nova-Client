import 'package:flutter/material.dart';

import '../core/proxy/proxy_controller.dart';
import 'nova_colors.dart';

/// Status / signal colors taken verbatim from the native Android Nova design
/// (`compose/theme/Color.kt`). These are theme-independent on purpose: the
/// native app uses the same bright greens/ambers/reds in light and dark so the
/// "connected" green and ping bars read identically across themes.
abstract final class NovaSemantics {
  /// Connect / "Secure" green (orb + button when connected).
  static const Color connectGreen = Color(0xFF22C55E);

  /// Brighter success green used for badges, labels, latency "good".
  static const Color successGreen = Color(0xFF34D399);

  /// Deep success (gradient end).
  static const Color emerald = Color(0xFF10B981);

  /// Busy / warning amber.
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberWarm = Color(0xFFF97316);
  static const Color amberSoft = Color(0xFFFB923C);

  /// Error / "bad latency" red.
  static const Color red = Color(0xFFEF4444);
  static const Color redSoft = Color(0xFFF87171);

  /// Teal used as the second stop of usage bars.
  static const Color teal = Color(0xFF14B8A6);

  /// Latency → color, mirroring the native ping scale
  /// (<150ms green, 150–299 amber, ≥300 red).
  static Color ping(int? ms) {
    if (ms == null) return const Color(0xFF9AA4B8);
    if (ms < 150) return connectGreen;
    if (ms < 300) return const Color(0xFFF5B301);
    return red;
  }
}

/// The accent + gradient + glow for the connect control, keyed off the live
/// connection state — the signature cyan→violet when off, green when
/// connected, amber while busy (matches `NovaConnectButton`/`NovaConnectOrb`).
class NovaConnectVisual {
  const NovaConnectVisual({
    required this.accent,
    required this.gradient,
  });

  final Color accent;
  final List<Color> gradient;

  Gradient linear({
    AlignmentGeometry begin = Alignment.topLeft,
    AlignmentGeometry end = Alignment.bottomRight,
  }) =>
      LinearGradient(colors: gradient, begin: begin, end: end);

  static NovaConnectVisual of(ProxyConnectionState state, NovaColors c) {
    switch (state) {
      case ProxyConnectionState.connected:
        return const NovaConnectVisual(
          accent: NovaSemantics.connectGreen,
          gradient: [NovaSemantics.connectGreen, Color(0xFF16A34A)],
        );
      case ProxyConnectionState.connecting:
      case ProxyConnectionState.disconnecting:
        return const NovaConnectVisual(
          accent: NovaSemantics.amber,
          gradient: [NovaSemantics.amber, NovaSemantics.amberWarm],
        );
      case ProxyConnectionState.disconnected:
      case ProxyConnectionState.error:
        return NovaConnectVisual(
          accent: c.cyan,
          gradient: [c.cyan, c.violet],
        );
    }
  }
}
