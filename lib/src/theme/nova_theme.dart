import 'package:flutter/material.dart';

import 'nova_colors.dart';
import 'nova_radii.dart';
import 'nova_typography.dart';

/// Builds the Material [ThemeData] for Nova Client from the design tokens.
class NovaTheme {
  const NovaTheme._();

  static ThemeData dark(Locale locale) => _build(NovaColors.dark, locale);

  static ThemeData light(Locale locale) => _build(NovaColors.light, locale);

  static ThemeData _build(NovaColors c, Locale locale) {
    final TextTheme textTheme = NovaTypography.textTheme(
      color: c.text,
      muted: c.muted,
      locale: locale,
    );

    final ColorScheme scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.cyan,
      onPrimary: c.onAccent,
      secondary: c.violet,
      onSecondary: c.onAccent,
      tertiary: c.indigo,
      onTertiary: c.onAccent,
      error: c.danger,
      onError: c.onAccent,
      surface: c.bgAlt,
      onSurface: c.text,
      surfaceContainerHighest: c.surface2,
      outline: c.borderStrong,
      outlineVariant: c.border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      textTheme: textTheme,
      primaryColor: c.cyan,
      dividerColor: c.border,
      splashColor: c.cyan.withValues(alpha: 0.10),
      highlightColor: c.cyan.withValues(alpha: 0.06),
      extensions: <ThemeExtension<dynamic>>[NovaColorsExt(c)],
      iconTheme: IconThemeData(color: c.text, size: 22),
      appBarTheme: AppBarTheme(
        backgroundColor: c.navBg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: NovaRadii.cardR,
          side: BorderSide(color: c.border),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: c.border,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.onAccent
              : c.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.cyan
              : c.surface2,
        ),
        trackOutlineColor: WidgetStateProperty.all(c.border),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NovaSpace.lg,
          vertical: NovaSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: NovaRadii.smR,
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NovaRadii.smR,
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NovaRadii.smR,
          borderSide: BorderSide(color: c.cyan, width: 1.5),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.codeBg,
        contentTextStyle: textTheme.bodyMedium,
        actionTextColor: c.cyan,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: NovaRadii.smR),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.codeBg,
          borderRadius: NovaRadii.smR,
          border: Border.all(color: c.border),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: c.text),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.cyan,
        linearTrackColor: c.surface2,
        circularTrackColor: c.surface2,
      ),
    );
  }
}

/// Convenience accessor for the Nova tokens carried on the active [Theme].
extension NovaThemeContext on BuildContext {
  NovaColors get nova =>
      Theme.of(this).extension<NovaColorsExt>()?.colors ?? NovaColors.dark;
}
