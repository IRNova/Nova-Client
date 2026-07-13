import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/proxy/conn_info_controller.dart';
import 'core/proxy/proxy_controller.dart';
import 'features/cloudflare/cloudflare_controller.dart';
import 'features/profiles/profiles_controller.dart';
import 'features/radar/radar_controller.dart';
import 'features/settings/settings_controller.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'l10n/nova_strings.dart';
import 'theme/nova_theme.dart';
import 'theme/theme_controller.dart';
import 'widgets/nova_app_shell.dart';
import 'widgets/nova_logo.dart';
import 'widgets/nova_scope.dart';

/// The Nova Client application root. Owns the long-lived controllers, exposes
/// them through [NovaScope], and rebuilds [MaterialApp] when the theme or
/// locale changes.
class NovaApp extends StatelessWidget {
  const NovaApp({
    super.key,
    required this.theme,
    required this.proxy,
    required this.connInfo,
    required this.profiles,
    required this.radar,
    required this.cloudflare,
    required this.settings,
  });

  final ThemeController theme;
  final ProxyController proxy;
  final ConnInfoController connInfo;
  final ProfilesController profiles;
  final RadarController radar;
  final CloudflareController cloudflare;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return NovaScope(
      theme: theme,
      proxy: proxy,
      connInfo: connInfo,
      profiles: profiles,
      radar: radar,
      cloudflare: cloudflare,
      settings: settings,
      child: ListenableBuilder(
        listenable: theme,
        builder: (context, _) {
          return MaterialApp(
            title: 'Nova Client',
            debugShowCheckedModeBanner: false,
            themeMode: theme.themeMode,
            theme: NovaTheme.light(theme.locale),
            darkTheme: NovaTheme.dark(theme.locale),
            locale: theme.locale,
            supportedLocales: ThemeController.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              NovaStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _RootGate(theme: theme),
          );
        },
      ),
    );
  }
}

/// Chooses between onboarding and the app shell once prefs have loaded, and
/// carries the onboarding "how to start" choice into the shell.
class _RootGate extends StatefulWidget {
  const _RootGate({required this.theme});
  final ThemeController theme;

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> with WidgetsBindingObserver {
  String? _startAction;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sync the real tunnel state once the tree is up (covers cold launch while
    // the VPN is already running).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) NovaScope.of(context).proxy.syncStatus();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On return to foreground, re-read the tunnel state so a still-connected
    // VPN isn't shown as off.
    if (state == AppLifecycleState.resumed && mounted) {
      NovaScope.of(context).proxy.syncStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.theme,
      builder: (context, _) {
        if (!widget.theme.loaded) {
          return const Scaffold(body: Center(child: NovaLogo(size: 72)));
        }
        if (!widget.theme.onboarded) {
          return NovaOnboarding(
            onPickLanguage: (String code) => widget.theme.setLocale(Locale(code)),
            onFinish: (String? action) {
              widget.theme.setOnboarded();
              setState(() => _startAction = action);
            },
          );
        }
        return NovaAppShell(startAction: _startAction);
      },
    );
  }
}
