import 'package:flutter/material.dart';

/// Nova Proxy color tokens.
///
/// Ported verbatim from the Nova Proxy design system
/// (`irnova-site/design-system/tokens.css`) so the app shares one visual
/// language with the marketing site, the in-Worker dashboard and the Telegram
/// Mini App. Dark is the default theme; [NovaColors.light] mirrors the opt-in
/// `data-theme="light"` block.
@immutable
class NovaColors {
  const NovaColors({
    required this.brightness,
    required this.cyan,
    required this.violet,
    required this.indigo,
    required this.indigoStrong,
    required this.onAccent,
    required this.bg,
    required this.bgAlt,
    required this.surface,
    required this.surface2,
    required this.navBg,
    required this.codeBg,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.onPill,
    required this.success,
    required this.successStrong,
    required this.warning,
    required this.info,
    required this.danger,
    required this.star,
  });

  final Brightness brightness;

  // ---- Brand accents ----
  /// Primary accent — links, eyebrows, focus rings.
  final Color cyan;

  /// Secondary accent.
  final Color violet;

  /// Gradient midpoint / featured highlights.
  final Color indigo;

  /// Badges, emphasis on light surfaces.
  final Color indigoStrong;

  /// Foreground placed on top of the signature gradient (dark ink reads on the
  /// bright gradient in both themes).
  final Color onAccent;

  // ---- Backgrounds & surfaces ----
  final Color bg;
  final Color bgAlt;
  final Color surface;
  final Color surface2;
  final Color navBg;
  final Color codeBg;

  // ---- Borders ----
  final Color border;
  final Color borderStrong;

  // ---- Text ----
  final Color text;
  final Color muted;
  final Color onPill;

  // ---- State / feedback ----
  final Color success;
  final Color successStrong;
  final Color warning;
  final Color info;
  final Color danger;
  final Color star;

  /// Dark theme — the Nova default.
  static const NovaColors dark = NovaColors(
    brightness: Brightness.dark,
    cyan: Color(0xFF22D3EE),
    violet: Color(0xFF9D4EFB), // matches native Android NovaViolet
    indigo: Color(0xFF7C5CFF), // matches native Android NovaIndigo
    indigoStrong: Color(0xFF6366F1),
    onAccent: Color(0xFF05060A),
    bg: Color(0xFF070809), // native Android NovaBackground
    bgAlt: Color(0xFF0C0E13),
    surface: Color(0x12FFFFFF), // ~surface card fill, a touch more visible
    surface2: Color(0x1AFFFFFF), // selected/raised surface
    navBg: Color(0xB305060A), // rgba(5,6,10,0.7)
    codeBg: Color(0xFF0B0E16),
    border: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    borderStrong: Color(0x29FFFFFF), // rgba(255,255,255,0.16)
    text: Color(0xFFEEF1F7),
    muted: Color(0xFF9AA4B8),
    onPill: Color(0xFFCFE8FF),
    success: Color(0xFF7EE0B8),
    successStrong: Color(0xFF047857),
    warning: Color(0xFFF59E0B),
    info: Color(0xFFA855F7),
    danger: Color(0xFFEF4444),
    star: Color(0xFFFFD479),
  );

  /// Light theme — opt-in (`data-theme="light"`). Accents are slightly deepened
  /// to keep contrast on the light background, matching the token file.
  static const NovaColors light = NovaColors(
    brightness: Brightness.light,
    cyan: Color(0xFF0891B2),
    violet: Color(0xFF9333EA),
    indigo: Color(0xFF818CF8),
    indigoStrong: Color(0xFF6366F1),
    onAccent: Color(0xFF05060A),
    bg: Color(0xFFF7F8FC),
    bgAlt: Color(0xFFEEF1F7),
    surface: Color(0x0A0F172A), // rgba(15,23,42,0.04)
    surface2: Color(0x120F172A), // rgba(15,23,42,0.07)
    navBg: Color(0xCCF7F8FC), // rgba(247,248,252,0.8)
    codeBg: Color(0xFFEEF1F7),
    border: Color(0x1F0F172A), // rgba(15,23,42,0.12)
    borderStrong: Color(0x380F172A), // rgba(15,23,42,0.22)
    text: Color(0xFF0D1117),
    muted: Color(0xFF51607A),
    onPill: Color(0xFF0E7490),
    success: Color(0xFF047857),
    successStrong: Color(0xFF047857),
    warning: Color(0xFFF59E0B),
    info: Color(0xFF9333EA),
    danger: Color(0xFFEF4444),
    star: Color(0xFFB45309),
  );
}

/// Exposes [NovaColors] through the [Theme] via [ThemeExtension] so widgets can
/// read Nova tokens with `Theme.of(context).extension<NovaColorsExt>()`.
@immutable
class NovaColorsExt extends ThemeExtension<NovaColorsExt> {
  const NovaColorsExt(this.colors);

  final NovaColors colors;

  @override
  NovaColorsExt copyWith({NovaColors? colors}) =>
      NovaColorsExt(colors ?? this.colors);

  @override
  NovaColorsExt lerp(ThemeExtension<NovaColorsExt>? other, double t) {
    // Themes are discrete (dark/light); snap rather than interpolate tokens.
    if (other is! NovaColorsExt) return this;
    return t < 0.5 ? this : other;
  }
}
