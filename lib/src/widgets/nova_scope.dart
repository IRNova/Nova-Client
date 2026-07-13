import 'package:flutter/widgets.dart';

import '../core/proxy/conn_info_controller.dart';
import '../core/proxy/proxy_controller.dart';
import '../features/cloudflare/cloudflare_controller.dart';
import '../features/profiles/profiles_controller.dart';
import '../features/radar/radar_controller.dart';
import '../features/settings/settings_controller.dart';
import '../theme/theme_controller.dart';

/// A lightweight dependency locator for the app's long-lived controllers.
///
/// The controllers are created once at startup and never swapped, so this
/// inherited widget never needs to notify; UI rebuilds come from the
/// controllers themselves (each is a [ChangeNotifier], consumed via
/// [ListenableBuilder]). This keeps the app dependency-free of an external
/// state-management package while staying idiomatic.
class NovaScope extends InheritedWidget {
  const NovaScope({
    super.key,
    required this.theme,
    required this.proxy,
    required this.connInfo,
    required this.profiles,
    required this.radar,
    required this.cloudflare,
    required this.settings,
    required super.child,
  });

  final ThemeController theme;
  final ProxyController proxy;
  final ConnInfoController connInfo;
  final ProfilesController profiles;
  final RadarController radar;
  final CloudflareController cloudflare;
  final SettingsController settings;

  static NovaScope of(BuildContext context) {
    final NovaScope? scope =
        context.dependOnInheritedWidgetOfExactType<NovaScope>();
    assert(scope != null, 'NovaScope.of() called with no NovaScope in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(NovaScope oldWidget) =>
      theme != oldWidget.theme ||
      proxy != oldWidget.proxy ||
      connInfo != oldWidget.connInfo ||
      profiles != oldWidget.profiles ||
      radar != oldWidget.radar ||
      cloudflare != oldWidget.cloudflare ||
      settings != oldWidget.settings;
}
