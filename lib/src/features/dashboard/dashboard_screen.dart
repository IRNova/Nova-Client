import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/proxy_profile.dart';
import '../../core/proxy/conn_info_controller.dart';
import '../../core/proxy/proxy_controller.dart';
import '../../core/proxy/subscription.dart';
import '../../core/util/format.dart';
import '../../l10n/nova_strings.dart';
import '../../theme/nova_radii.dart';
import '../../theme/nova_semantics.dart';
import '../../theme/nova_theme.dart';
import '../../widgets/nova_components.dart';
import '../../widgets/nova_connect_orb.dart';
import '../../widgets/nova_logo.dart';
import '../../widgets/nova_scope.dart';
import '../../widgets/nova_segmented_tabs.dart';
import '../cloudflare/cloudflare_controller.dart';
import '../cloudflare/cloudflare_screen.dart';
import '../cloudflare/deploy_screen.dart';
import '../radar/radar_screen.dart';
import '../servers/servers_body.dart';

/// The home screen — a faithful port of the native Android dashboard:
/// a Summary/Configs segmented header, a Cloudflare chip, the connect orb with
/// a live uptime timer, a metrics block (exit country/IP/ping + up/down speed),
/// the active config card, and a tools row.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.resetToSummary});

  /// Notified by the app shell whenever the Home tab is tapped, so the screen
  /// returns to its Summary segment.
  final Listenable? resetToSummary;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _tab = 0; // 0 = Summary, 1 = Configs

  @override
  void initState() {
    super.initState();
    widget.resetToSummary?.addListener(_backToSummary);
  }

  @override
  void didUpdateWidget(DashboardScreen old) {
    super.didUpdateWidget(old);
    if (old.resetToSummary != widget.resetToSummary) {
      old.resetToSummary?.removeListener(_backToSummary);
      widget.resetToSummary?.addListener(_backToSummary);
    }
  }

  @override
  void dispose() {
    widget.resetToSummary?.removeListener(_backToSummary);
    super.dispose();
  }

  void _backToSummary() {
    if (mounted && _tab != 0) setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    final scope = NovaScope.of(context);
    final s = NovaStrings.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        scope.proxy,
        scope.profiles,
        scope.cloudflare,
        // So the hero's "Verifying…/Secure" subtitle flips the moment a probe
        // confirms traffic is actually getting through the tunnel.
        scope.connInfo,
      ]),
      builder: (context, _) {
        final proxy = scope.proxy;
        final active = scope.profiles.active;
        // Keep the proxy's selected profile in sync with the active profile.
        if (proxy.activeProfile?.id != active?.id) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            proxy.selectProfile(active);
          });
        }

        final int configCount = scope.profiles.profiles.length;

        return Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: NovaSpace.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              children: <Widget>[
                const _HomeHeader(),
                const SizedBox(height: 14),
                NovaSegmentedTabs(
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                  segments: <NovaSegment>[
                    NovaSegment(label: s.t('home.summary'), icon: Icons.home_rounded),
                    NovaSegment(
                      label: s.t('home.configs'),
                      icon: Icons.grid_view_rounded,
                      badge: configCount,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _CloudflareChip(),
                const SizedBox(height: 14),
                if (_tab == 0)
                  _SummaryView(proxy: proxy)
                else
                  const ServersBody(compact: true),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final s = NovaStrings.of(context);
    return Row(
      children: <Widget>[
        Text(
          s.t('home.title'),
          style: Theme.of(context)
              .textTheme
              .headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        const NovaLogo(size: 34),
      ],
    );
  }
}

/// Full-width Cloudflare status chip → opens the Cloudflare hub.
class _CloudflareChip extends StatelessWidget {
  const _CloudflareChip();

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    final cf = NovaScope.of(context).cloudflare;
    final bool connected = cf.phase == CfPhase.connected;
    final text = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const CloudflareScreen()),
      ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: nova.surface,
          borderRadius: NovaRadii.chipR,
          border: Border.all(color: nova.border.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_rounded, size: 17, color: nova.cyan),
            const SizedBox(width: 10),
            Expanded(
              child: connected
                  ? Text.rich(
                      TextSpan(children: <InlineSpan>[
                        TextSpan(
                          text: '${s.cfConnectedTo}  ',
                          style: text.labelLarge
                              ?.copyWith(color: nova.muted, fontSize: 12),
                        ),
                        TextSpan(
                          text: cf.accountName.isEmpty ? '·' : cf.accountName,
                          style: text.labelLarge?.copyWith(
                            color: NovaSemantics.successGreen,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ]),
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      s.cfConnect,
                      style: text.labelLarge?.copyWith(
                        color: nova.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: nova.muted),
          ],
        ),
      ),
    );
  }
}

/// The Summary tab: orb + uptime hero, metrics, config card, tools.
class _SummaryView extends StatefulWidget {
  const _SummaryView({required this.proxy});
  final ProxyController proxy;

  @override
  State<_SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<_SummaryView> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_SummaryView old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.proxy.state.isActive) {
      _ticker ??= Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() {}));
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final proxy = widget.proxy;
    final scope = NovaScope.of(context);
    final bool hasProfile = scope.profiles.active != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 6),
        _ConnectHero(proxy: proxy, hasProfile: hasProfile),
        SizedBox(height: proxy.state.isActive ? 20 : 24),
        _MetricsBlock(proxy: proxy),
        if (hasProfile) ...<Widget>[
          const SizedBox(height: 10),
          _ConfigCard(),
        ],
        const SizedBox(height: 10),
        const _ToolsRow(),
      ],
    );
  }
}

/// The centered connect hero: a single status pill, the orb, and a state
/// headline + subtitle. Centering the primary control (rather than the old
/// orb-left / text-right split) matches the pattern top VPN clients use — the
/// connect action is the emotional centerpiece of the screen.
class _ConnectHero extends StatelessWidget {
  const _ConnectHero({required this.proxy, required this.hasProfile});

  final ProxyController proxy;
  final bool hasProfile;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    final text = Theme.of(context).textTheme;
    final ProxyConnectionState state = proxy.state;
    final bool connected = state == ProxyConnectionState.connected;
    // Honest reachability: the tunnel can report "connected" while a dead exit
    // (or an urltest that hasn't settled on a live node yet) carries no traffic.
    // Until a probe actually gets through we say "Verifying…", not "Secure", so
    // a green orb never lies about a working connection.
    final bool reachable = NovaScope.of(context).connInfo.info.reachable;

    // Status pill — distinct color/label per state, not just active/inactive,
    // so "Connecting…" and errors read correctly instead of "Not connected".
    final (Color, String) badge = switch (state) {
      ProxyConnectionState.connected => (NovaSemantics.successGreen, s.connected),
      ProxyConnectionState.connecting ||
      ProxyConnectionState.disconnecting =>
        (NovaSemantics.amber, s.connecting),
      ProxyConnectionState.error => (nova.danger, s.dashError),
      ProxyConnectionState.disconnected => (nova.muted, s.disconnected),
    };

    // Headline + optional subtitle. The subtitle is dropped when it would just
    // echo the pill (idle / connecting), so the same words never appear twice.
    String headline;
    String? subtitle;
    Color subtitleColor = nova.muted;
    bool headlineIsTimer = false;
    switch (state) {
      case ProxyConnectionState.connected:
        headline = Fmt.uptime(proxy.connectedSince);
        headlineIsTimer = true;
        subtitle = reachable ? s.dashSecure : s.dashVerifying;
        subtitleColor =
            reachable ? NovaSemantics.connectGreen : NovaSemantics.amber;
      case ProxyConnectionState.connecting:
      case ProxyConnectionState.disconnecting:
        headline = s.connecting;
      case ProxyConnectionState.error:
        headline = s.dashError;
        subtitle = proxy.lastError;
        subtitleColor = nova.danger;
      case ProxyConnectionState.disconnected:
        headline = s.tapToConnect;
    }

    return Column(
      children: <Widget>[
        NovaStatusBadge(label: badge.$2, color: badge.$1),
        const SizedBox(height: 22),
        NovaConnectOrb(
          state: state,
          size: 172,
          onTap: hasProfile || connected ? proxy.toggle : null,
        ),
        const SizedBox(height: 22),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: headlineIsTimer
              ? text.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 44,
                  height: 1.0,
                  letterSpacing: -1,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                )
              : text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: text.titleSmall?.copyWith(
              color: subtitleColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

/// Country/IP/ping row + download/upload speed tiles.
class _MetricsBlock extends StatelessWidget {
  const _MetricsBlock({required this.proxy});
  final ProxyController proxy;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final connInfo = NovaScope.of(context).connInfo;
    final bool active = proxy.state.isActive;

    return ListenableBuilder(
      listenable: connInfo,
      builder: (context, _) {
        final ConnInfo info = connInfo.info;
        final bool loading = connInfo.loading;
        final String country = !active
            ? '—'
            : info.hasGeo
                ? (info.countryCode ?? '—')
                : (loading ? '…' : '—');
        final String ip = !active
            ? '—'
            : (info.ip ?? (loading ? '…' : '—'));
        final String ping = !active
            ? '—'
            : info.pingMs != null
                ? '${info.pingMs} ms'
                : (loading ? '…' : '—');

        return Column(
          children: <Widget>[
            // Connection-detail card: a clean labeled Location / IP / Ping strip
            // when connected, or a calm "not protected" prompt when idle (rather
            // than repeating "Not connected" in a near-empty card).
            if (active)
              _ConnDetailStrip(
                country: country,
                countryCode: info.hasGeo ? info.countryCode : null,
                ip: ip,
                ping: ping,
                pingMs: info.pingMs,
              )
            else
              const _NotProtectedCard(),
            // Live throughput tiles only matter while connected — when idle
            // they would just read "—" and push the tools row below the fold.
            if (active) ...<Widget>[
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SpeedTile(
                      label: NovaStrings.of(context).download,
                      icon: Icons.arrow_downward_rounded,
                      color: nova.cyan,
                      value: Fmt.bps(proxy.traffic.downlinkBps),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SpeedTile(
                      label: NovaStrings.of(context).upload,
                      icon: Icons.arrow_upward_rounded,
                      color: nova.violet,
                      value: Fmt.bps(proxy.traffic.uplinkBps),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The live connection detail: three labeled stats (location, IP, ping) split
/// by hairline dividers. Reads like a status panel in an enterprise console.
class _ConnDetailStrip extends StatelessWidget {
  const _ConnDetailStrip({
    required this.country,
    required this.countryCode,
    required this.ip,
    required this.ping,
    required this.pingMs,
  });

  final String country;
  final String? countryCode;
  final String ip;
  final String ping;
  final int? pingMs;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    final Widget divider = Container(width: 1, color: nova.border);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: nova.surface,
        borderRadius: NovaRadii.heroR,
        border: Border.all(color: nova.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _DetailStat(
                label: s.dashLocation,
                value: country,
                leading: countryCode != null
                    ? NovaCountryFlag(iso2: countryCode, size: 15)
                    : null,
              ),
            ),
            divider,
            Expanded(child: _DetailStat(label: s.dashIp, value: ip)),
            divider,
            Expanded(
              child: _DetailStat(
                label: 'PING',
                value: ping,
                valueColor: pingMs != null ? NovaSemantics.ping(pingMs) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({
    required this.label,
    required this.value,
    this.leading,
    this.valueColor,
  });

  final String label;
  final String value;
  final Widget? leading;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: text.labelSmall?.copyWith(
            color: nova.muted,
            fontSize: 10,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Idle connection card: a calm "you're not protected yet" prompt that nudges
/// the user to connect, replacing a near-empty card that just said "Not
/// connected" again.
class _NotProtectedCard extends StatelessWidget {
  const _NotProtectedCard();

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: nova.surface,
        borderRadius: NovaRadii.heroR,
        border: Border.all(color: nova.border),
      ),
      child: Row(
        children: <Widget>[
          NovaIconChip(
            icon: Icons.shield_outlined,
            color: nova.muted,
            size: 42,
            radius: 12,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.dashNotProtected,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  s.dashNotProtectedBody,
                  style: text.bodySmall?.copyWith(color: nova.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: nova.surface,
        borderRadius: NovaRadii.cardR,
        border: Border.all(color: nova.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              NovaIconChip(icon: icon, color: color, size: 26, radius: 8),
              const SizedBox(width: 8),
              Text(label.toUpperCase(),
                  style: text.labelSmall?.copyWith(
                    color: nova.muted,
                    letterSpacing: 0.6,
                  )),
            ],
          ),
          const SizedBox(height: 10),
          Text(value,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The active config / server summary card.
class _ConfigCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    final scope = NovaScope.of(context);
    final active = scope.profiles.active!;
    final text = Theme.of(context).textTheme;
    final int? latency = active.lastLatencyMs;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: nova.surface,
        borderRadius: NovaRadii.heroR,
        border: Border.all(color: nova.border),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              NovaIconChip(
                icon: active.isSubscription
                    ? Icons.cloud_sync_rounded
                    : Icons.dns_rounded,
                color: nova.indigo,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(active.name,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        NovaProtocolBadge(
                          label: active.kind.label,
                          color: nova.cyan,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active.isSubscription
                          ? s.nodesCount(active.nodeCount)
                          : s.homeSingleConfig,
                      style: text.bodySmall?.copyWith(color: nova.muted),
                    ),
                  ],
                ),
              ),
              if (latency != null)
                Row(
                  children: <Widget>[
                    Text('$latency ms',
                        style: text.titleSmall?.copyWith(
                          color: NovaSemantics.successGreen,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(width: 6),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: NovaSemantics.successGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: nova.border),
          ),
          Row(
            children: <Widget>[
              // Uptime is intentionally omitted here — the hero already shows it
              // as the big timer, so repeating it as a "TIME" metric was
              // redundant. This card sticks to plan info (data + expiry).
              _ConfigMetric(
                icon: Icons.data_usage_rounded,
                label: s.homeData,
                value: () {
                  final SubInfo? s = subInfoFor(active.subscriptionUrl);
                  if (s == null) return '∞';
                  return s.total > 0
                      ? '${Fmt.bytes(s.used)} / ${Fmt.bytes(s.total)}'
                      : Fmt.bytes(s.used);
                }(),
              ),
              _ConfigMetric(
                icon: Icons.calendar_month_rounded,
                label: s.homeExpiry,
                value: () {
                  final DateTime? e = subInfoFor(active.subscriptionUrl)?.expire;
                  if (e == null) return '—';
                  return '${e.year}-${e.month.toString().padLeft(2, '0')}-'
                      '${e.day.toString().padLeft(2, '0')}';
                }(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfigMetric extends StatelessWidget {
  const _ConfigMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: <Widget>[
          Icon(icon, size: 14, color: nova.muted),
          const SizedBox(height: 5),
          Text(label.toUpperCase(),
              style: text.labelSmall
                  ?.copyWith(color: nova.muted, fontSize: 10, letterSpacing: 0.6)),
          const SizedBox(height: 3),
          Text(value,
              style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Radar / Deploy / Panel quick-access tiles.
class _ToolsRow extends StatelessWidget {
  const _ToolsRow();

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: _ToolCard(
            icon: Icons.radar_rounded,
            label: s.navRadar,
            color: nova.cyan,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RadarScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ToolCard(
            icon: Icons.cloud_upload_rounded,
            label: s.toolDeploy,
            color: nova.indigo,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DeployScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ToolCard(
            icon: Icons.dashboard_rounded,
            label: s.toolPanel,
            color: nova.violet,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CloudflareScreen()),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: nova.surface,
          borderRadius: NovaRadii.toolR,
          border: Border.all(color: nova.border),
        ),
        child: Column(
          children: <Widget>[
            NovaIconChip(icon: icon, color: color, size: 44, radius: 22),
            const SizedBox(height: 8),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
