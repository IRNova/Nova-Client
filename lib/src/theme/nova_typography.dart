import 'package:flutter/material.dart';

/// Nova Proxy typography tokens.
///
/// Latin UI uses Inter; Farsi/Arabic script uses Vazirmatn (selected at runtime
/// from the active locale). Font families resolve to system fallbacks when the
/// bundled font files are absent, so the app never crashes on a missing asset.
/// To ship the exact brand fonts, drop the Inter/Vazirmatn `.ttf` files under
/// `assets/fonts/` and declare them in `pubspec.yaml` (see the commented block
/// there).
class NovaTypography {
  const NovaTypography._();

  static const String fontSans = 'Inter';
  static const String fontFarsi = 'Vazirmatn';
  static const String fontMono = 'SFMono';

  static const List<String> sansFallback = <String>[
    'Inter',
    'SF Pro Text',
    'Segoe UI',
    'Roboto',
    'Helvetica',
    'Arial',
  ];

  static const List<String> farsiFallback = <String>[
    'Vazirmatn',
    'Inter',
    'Tahoma',
    'Arial',
  ];

  static const List<String> monoFallback = <String>[
    'SFMono',
    'Menlo',
    'Consolas',
    'monospace',
  ];

  // Weights mirror the design tokens.
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight black = FontWeight.w800;

  // Tracking.
  static const double trackingTight = -0.02; // headings (em-ish, in logical px)
  static const double trackingEyebrow = 0.16 * 12; // uppercased latin eyebrows

  /// Builds a [TextTheme] for [color] text, choosing the script-appropriate
  /// family for [locale].
  static TextTheme textTheme({
    required Color color,
    required Color muted,
    required Locale locale,
  }) {
    final bool isFarsi = locale.languageCode == 'fa';
    final String family = isFarsi ? fontFarsi : fontSans;
    final List<String> fallback = isFarsi ? farsiFallback : sansFallback;
    final double bodyHeight = isFarsi ? 1.75 : 1.6;

    TextStyle base(double size, FontWeight weight,
            {Color? c, double? height, double? spacing}) =>
        TextStyle(
          fontFamily: family,
          fontFamilyFallback: fallback,
          fontSize: size,
          fontWeight: weight,
          color: c ?? color,
          height: height,
          letterSpacing: spacing,
        );

    return TextTheme(
      // Display / hero.
      displayLarge: base(40, black, height: 1.15, spacing: trackingTight),
      displayMedium: base(34, black, height: 1.15, spacing: trackingTight),
      // Headings.
      headlineLarge: base(29, bold, height: 1.15, spacing: trackingTight),
      headlineMedium: base(24, bold, height: 1.2, spacing: trackingTight),
      headlineSmall: base(20, semibold, height: 1.25),
      titleLarge: base(18, semibold, height: 1.3),
      titleMedium: base(16, semibold, height: 1.35),
      titleSmall: base(14, semibold, height: 1.35),
      // Body.
      bodyLarge: base(16, regular, height: bodyHeight),
      bodyMedium: base(14.5, regular, height: bodyHeight, c: color),
      bodySmall: base(13, regular, height: bodyHeight, c: muted),
      // Labels.
      labelLarge: base(14, semibold, height: 1.2),
      labelMedium: base(13, medium, height: 1.2),
      labelSmall: base(11.5, medium, height: 1.2),
    );
  }
}
