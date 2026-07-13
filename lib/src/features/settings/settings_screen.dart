import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/nova_strings.dart';
import '../../theme/nova_radii.dart';
import '../../theme/nova_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/nova_card.dart';
import '../../widgets/nova_components.dart';
import '../../widgets/nova_logo.dart';
import '../../widgets/nova_pill.dart';
import '../../widgets/nova_scope.dart';
import '../cloudflare/cloudflare_screen.dart';
import '../radar/radar_screen.dart';
import '../routing/routing_screen.dart';

/// Shown in the Settings "About" footer so a tester can confirm exactly which
/// build is running. Keep in step with `pubspec.yaml`'s `version:` on release.
const String kNovaVersion = '0.2.0';
const String kNovaBuild = '59';

/// App settings — grouped cards (General · Appearance · Community · About) in
/// the native Android style, with colored leading icon chips and chevrons.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeController theme = NovaScope.of(context).theme;
    final s = NovaStrings.of(context);
    final nova = context.nova;

    return ListenableBuilder(
      listenable: theme,
      builder: (context, _) {
        return Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: NovaSpace.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: <Widget>[
                Text(s.navSettings,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 16),

                _SectionLabel(s.setGeneral),
                NovaCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _NavRow(
                        icon: Icons.alt_route_rounded,
                        color: nova.violet,
                        title: s.setRouting,
                        subtitle: s.setRoutingSub,
                        onTap: () => _push(context, const RoutingScreen()),
                      ),
                      _div(nova.border),
                      _NavRow(
                        icon: Icons.radar_rounded,
                        color: nova.cyan,
                        title: s.navRadar,
                        subtitle: s.setRadarSub,
                        onTap: () => _push(context, const RadarScreen()),
                      ),
                      _div(nova.border),
                      _NavRow(
                        icon: Icons.cloud_rounded,
                        color: nova.indigo,
                        title: s.setCloudflare,
                        subtitle: s.setCloudflareSub,
                        onTap: () => _push(context, const CloudflareScreen()),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _SectionLabel(s.setAppearance),
                NovaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _Row(
                        label: s.theme,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            NovaPill(
                              label: s.modeSystem,
                              icon: Icons.brightness_auto,
                              selected: theme.themeMode == ThemeMode.system,
                              onTap: () =>
                                  theme.setThemeMode(ThemeMode.system),
                            ),
                            NovaPill(
                              label: s.modeDark,
                              icon: Icons.dark_mode,
                              selected: theme.themeMode == ThemeMode.dark,
                              onTap: () => theme.setThemeMode(ThemeMode.dark),
                            ),
                            NovaPill(
                              label: s.modeLight,
                              icon: Icons.light_mode,
                              selected: theme.themeMode == ThemeMode.light,
                              onTap: () => theme.setThemeMode(ThemeMode.light),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Row(
                        label: s.language,
                        child: Wrap(
                          spacing: 8,
                          children: <Widget>[
                            NovaPill(
                              label: 'English',
                              selected: !theme.isFarsi,
                              onTap: () =>
                                  theme.setLocale(const Locale('en')),
                            ),
                            NovaPill(
                              label: 'فارسی',
                              selected: theme.isFarsi,
                              onTap: () =>
                                  theme.setLocale(const Locale('fa')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _SectionLabel(s.setCommunity),
                NovaCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      _LinkTile(
                        icon: Icons.language,
                        title: 'novaproxy.online',
                        url: 'https://novaproxy.online/',
                      ),
                      _div(nova.border),
                      _LinkTile(
                        icon: Icons.send,
                        title: 'Telegram - @irnova_proxy',
                        url: 'https://t.me/irnova_proxy',
                      ),
                      _div(nova.border),
                      _LinkTile(
                        icon: Icons.camera_alt_rounded,
                        title: 'Instagram - @irnova_proxy',
                        url: 'https://instagram.com/irnova_proxy',
                      ),
                      _div(nova.border),
                      _LinkTile(
                        icon: Icons.code,
                        title: 'GitHub - IRNova',
                        url: 'https://github.com/IRNova',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                Center(
                  child: Column(
                    children: <Widget>[
                      const NovaLogo(size: 48),
                      const SizedBox(height: 8),
                      Text('Nova',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('v$kNovaVersion ($kNovaBuild)',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: nova.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Widget _div(Color c) => Divider(height: 1, color: c, indent: 56);

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: context.nova.cyan,
                fontWeight: FontWeight.w700,
              )),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            NovaIconChip(icon: icon, color: color, size: 32, radius: 9),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: text.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: text.bodySmall?.copyWith(color: nova.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: nova.muted),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        child,
      ],
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.title, required this.url});
  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return ListTile(
      leading: Icon(icon, color: nova.cyan),
      title: Text(title, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Icon(Icons.open_in_new, size: 16, color: nova.muted),
      onTap: () async {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}
