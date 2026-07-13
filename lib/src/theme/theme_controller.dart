import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user-selected [ThemeMode] and [Locale] and persists them.
///
/// Nova is dark-first (the design tokens default to the dark theme) and
/// bilingual (English + فارسی), so this controller drives both the visual
/// theme and the text direction of the whole app.
class ThemeController extends ChangeNotifier {
  ThemeController({SharedPreferences? prefs}) : _prefs = prefs {
    _load();
  }

  static const _kThemeKey = 'nova.themeMode';
  static const _kLocaleKey = 'nova.locale';
  static const _kOnboardedKey = 'nova.onboarded';

  /// Locales Nova ships with. English (LTR) and Persian/Farsi (RTL).
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  SharedPreferences? _prefs;

  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  bool get isFarsi => _locale.languageCode == 'fa';

  // Whether the first-run onboarding is complete, and whether prefs have loaded
  // yet (so the root can avoid flashing onboarding for returning users).
  bool _onboarded = false;
  bool get onboarded => _onboarded;
  bool _loaded = false;
  bool get loaded => _loaded;

  void _load() {
    final prefs = _prefs;
    if (prefs == null) return;
    final theme = prefs.getString(_kThemeKey);
    if (theme != null) {
      _themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == theme,
        orElse: () => ThemeMode.dark,
      );
    }
    final lang = prefs.getString(_kLocaleKey);
    if (lang != null) {
      _locale = Locale(lang);
    }
    _onboarded = prefs.getBool(_kOnboardedKey) ?? false;
  }

  /// Attaches a [SharedPreferences] instance after async init and reloads.
  void attachPrefs(SharedPreferences prefs) {
    _prefs = prefs;
    _load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setOnboarded() async {
    _onboarded = true;
    notifyListeners();
    await _prefs?.setBool(_kOnboardedKey, true);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs?.setString(_kThemeKey, mode.name);
  }

  Future<void> toggleBrightness() {
    return setThemeMode(
      _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode == _locale.languageCode) return;
    _locale = locale;
    notifyListeners();
    await _prefs?.setString(_kLocaleKey, locale.languageCode);
  }
}
