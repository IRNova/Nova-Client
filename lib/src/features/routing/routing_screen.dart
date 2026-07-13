import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/proxy/singbox/singbox_config.dart';
import '../../l10n/nova_strings.dart';
import '../../theme/nova_radii.dart';
import '../../theme/nova_theme.dart';
import '../../widgets/nova_card.dart';
import '../../widgets/nova_pill.dart';
import '../../widgets/nova_scope.dart';
import '../settings/settings_controller.dart';

/// Whether the full-device TUN option applies (it is a desktop-only data path).
final bool _isDesktop =
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Routing mode, rule toggles, and DNS resolver. These compile into the
/// sing-box config the core runs, so the choices here actually change how
/// traffic is routed and resolved (persisted via [SettingsController]).
class RoutingScreen extends StatelessWidget {
  const RoutingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = NovaStrings.of(context);
    final nova = context.nova;
    final SettingsController settings = NovaScope.of(context).settings;

    // A themed Scaffold is required: this is a pushed route, and without one it
    // renders with no background (black) so the light theme never shows — the
    // "Rules & DNS stuck in dark mode" report. The Scaffold gives it the app's
    // real background plus a back button.
    return Scaffold(
      appBar: AppBar(title: Text(s.navRouting)),
      body: ListenableBuilder(
        listenable: settings,
        builder: (BuildContext context, _) {
          return Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: NovaSpace.maxContentWidth),
              child: ListView(
                padding: const EdgeInsets.all(NovaSpace.xl),
                children: <Widget>[
                  Text(s.navRouting,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: NovaSpace.lg),
                NovaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const NovaEyebrow('Mode'),
                      const SizedBox(height: NovaSpace.md),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final SingboxMode m in SingboxMode.values)
                            NovaPill(
                              label: m.label,
                              icon: m.icon,
                              selected: settings.mode == m,
                              onTap: () => settings.setMode(m),
                            ),
                        ],
                      ),
                      const SizedBox(height: NovaSpace.sm),
                      Text(settings.mode.description,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: nova.muted)),
                    ],
                  ),
                ),
                const SizedBox(height: NovaSpace.lg),
                NovaCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _RuleSwitch(
                        icon: Icons.block,
                        title: 'Block ads & trackers',
                        subtitle: 'Drops known ad/tracker domains',
                        value: settings.blockAds,
                        onChanged: settings.setBlockAds,
                      ),
                      Divider(height: 1, color: nova.border),
                      _RuleSwitch(
                        icon: Icons.flag_outlined,
                        title: 'Direct for Iran (GeoIP/GeoSite)',
                        subtitle: 'Iranian destinations bypass the proxy',
                        value: settings.bypassIran,
                        onChanged: settings.setBypassIran,
                      ),
                      Divider(height: 1, color: nova.border),
                      _RuleSwitch(
                        icon: Icons.lan_outlined,
                        title: 'Bypass LAN',
                        subtitle: 'Private/local ranges stay direct',
                        value: settings.bypassLan,
                        onChanged: settings.setBypassLan,
                      ),
                    ],
                  ),
                ),
                if (_isDesktop) ...<Widget>[
                  const SizedBox(height: NovaSpace.lg),
                  NovaCard(
                    padding: EdgeInsets.zero,
                    child: _RuleSwitch(
                      icon: Icons.devices_rounded,
                      title: 'Full-device tunnel (TUN)',
                      subtitle:
                          'Route every app, not just proxy-aware ones. Needs '
                          'one admin approval when you connect.',
                      value: settings.tunMode,
                      onChanged: settings.setTunMode,
                    ),
                  ),
                ],
                const SizedBox(height: NovaSpace.lg),
                NovaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const NovaEyebrow('DNS resolver'),
                      const SizedBox(height: NovaSpace.md),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final NovaDnsChoice d in kNovaDnsChoices)
                            NovaPill(
                              label: d.label,
                              selected: settings.dns == d.server,
                              onTap: () => settings.setDns(d.server),
                            ),
                        ],
                      ),
                      const SizedBox(height: NovaSpace.sm),
                      Text(
                        'Encrypted DNS over HTTPS, resolved through the tunnel.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: nova.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: NovaSpace.md),
                Container(
                  padding: const EdgeInsets.all(NovaSpace.md),
                  decoration: BoxDecoration(
                    color: nova.info.withValues(alpha: 0.10),
                    borderRadius: NovaRadii.smR,
                    border: Border.all(color: nova.info.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.info_outline, size: 18, color: nova.info),
                      const SizedBox(width: NovaSpace.sm),
                      Expanded(
                        child: Text(
                          'Changes apply the next time you connect.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: nova.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

extension _RouteModeMeta on SingboxMode {
  String get label => switch (this) {
        SingboxMode.rule => 'Rule-based',
        SingboxMode.global => 'Global',
        SingboxMode.direct => 'Direct',
      };
  IconData get icon => switch (this) {
        SingboxMode.rule => Icons.alt_route,
        SingboxMode.global => Icons.public,
        SingboxMode.direct => Icons.arrow_forward,
      };
  String get description => switch (this) {
        SingboxMode.rule =>
          'Smart routing — proxy what needs it, keep the rest direct.',
        SingboxMode.global => 'Route all traffic through the proxy.',
        SingboxMode.direct => 'No proxying — everything goes direct.',
      };
}

class _RuleSwitch extends StatelessWidget {
  const _RuleSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: nova.cyan),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(subtitle,
          style:
              Theme.of(context).textTheme.bodySmall?.copyWith(color: nova.muted)),
    );
  }
}
