import 'package:flutter/widgets.dart';

/// The Nova signature gradient and helpers.
///
/// `--grad: linear-gradient(120deg, #22d3ee 0%, #818cf8 50%, #a855f7 100%)`
/// Used for primary buttons, the logo, gradient text, progress bars, active
/// toggles and the brand dot.
class NovaGradients {
  const NovaGradients._();

  static const Color cyan = Color(0xFF22D3EE);
  static const Color indigo = Color(0xFF7C5CFF);
  static const Color violet = Color(0xFF9D4EFB);

  /// The four-stop sweep used by the connect orb ring when idle
  /// (cyan → indigo → violet → cyan, matching native `NovaConnectOrb`).
  static const List<Color> orbSweepIdle = <Color>[cyan, indigo, violet, cyan];

  /// The orb ring sweep when connected (green family).
  static const List<Color> orbSweepConnected = <Color>[
    Color(0xFF22C55E),
    Color(0xFF34D399),
    Color(0xFF10B981),
    Color(0xFF22C55E),
  ];

  /// CSS `120deg` ≈ a vector pointing toward the upper-right. In CSS a 0deg
  /// gradient points up and angles increase clockwise, so 120deg runs from the
  /// lower-left toward the upper-right.
  static const LinearGradient signature = LinearGradient(
    begin: Alignment(-0.87, 0.5),
    end: Alignment(0.87, -0.5),
    colors: <Color>[cyan, indigo, violet],
    stops: <double>[0.0, 0.5, 1.0],
  );

  /// Two-stop brand gradient (`#22d3ee → #a855f7`) used by the logo mark.
  static const LinearGradient logo = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[cyan, violet],
  );

  /// A soft radial glow used behind hero elements (connect orb, radar dish).
  static RadialGradient glow(Color color, {double opacity = 0.35}) {
    return RadialGradient(
      colors: <Color>[
        color.withValues(alpha: opacity),
        color.withValues(alpha: 0.0),
      ],
    );
  }
}
