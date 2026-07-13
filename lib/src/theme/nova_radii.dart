import 'package:flutter/widgets.dart';

/// Layout tokens — radii, spacing scale, content width and elevation — from the
/// Nova design system.
class NovaRadii {
  const NovaRadii._();

  /// Native Nova shape scale (`compose/theme/Shape.kt` usage):
  /// primary cards 20, tool/stat cards 18, tiles/list rows 16,
  /// segmented tabs/search 14, chips/small surfaces 12, icon chips/badges 8.
  static const double hero = 20;
  static const double tool = 18;

  /// `--radius: 16px` — default card / tile radius.
  static const double card = 16;

  static const double tab = 14;
  static const double chip = 12;

  /// `--radius-sm: 10px` — inputs, small chips, notes.
  static const double sm = 10;

  /// Icon chips / badges.
  static const double iconChip = 8;

  /// `--radius-pill: 999px`.
  static const double pill = 999;

  static const BorderRadius heroR = BorderRadius.all(Radius.circular(hero));
  static const BorderRadius toolR = BorderRadius.all(Radius.circular(tool));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius tabR = BorderRadius.all(Radius.circular(tab));
  static const BorderRadius chipR = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius smR = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius iconChipR =
      BorderRadius.all(Radius.circular(iconChip));
  static const BorderRadius pillR = BorderRadius.all(Radius.circular(pill));
}

/// 4-pt spacing scale used throughout the app shell.
class NovaSpace {
  const NovaSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// `--maxw: 1140px` — max readable content width on wide windows.
  static const double maxContentWidth = 1140;
}

/// Elevation tokens.
class NovaElevation {
  const NovaElevation._();

  /// Primary-button lift. A restrained ambient shadow (enterprise, not neon):
  /// the button reads as raised without a saturated colored halo around it.
  static List<BoxShadow> accent(Color indigoStrong) => <BoxShadow>[
        BoxShadow(
          color: indigoStrong.withValues(alpha: 0.28),
          offset: const Offset(0, 8),
          blurRadius: 20,
          spreadRadius: -12,
        ),
      ];

  /// `--shadow-pop: 0 14px 30px rgba(0,0,0,0.35)` — menus / popovers.
  static const List<BoxShadow> pop = <BoxShadow>[
    BoxShadow(
      color: Color(0x59000000),
      offset: Offset(0, 14),
      blurRadius: 30,
    ),
  ];
}
