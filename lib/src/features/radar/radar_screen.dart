import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/proxy/singbox/nova_naming.dart';
import '../../core/util/format.dart';
import '../../l10n/nova_strings.dart';
import '../../theme/nova_radii.dart';
import '../../theme/nova_theme.dart';
import '../../widgets/nova_button.dart';
import '../../widgets/nova_card.dart';
import '../../widgets/nova_pill.dart';
import '../../widgets/nova_scope.dart';
import 'models.dart';
import 'radar_controller.dart';
import 'widgets/radar_sweep.dart';

/// Nova Radar — the consolidated Cloudflare clean-IP scanner. Fully functional:
/// it fetches sources, generates candidate IPs, runs the two-phase scan and
/// streams live results, all in the Nova design language.
class RadarScreen extends StatelessWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final RadarController radar = NovaScope.of(context).radar;
    final s = NovaStrings.of(context);

    // A themed Scaffold is essential here: Radar is a pushed route, and without
    // it the page renders with no background (black) so the muted ip:port text
    // becomes unreadable gray and the whole screen looks "dark" even in light
    // mode. The Scaffold gives the route the app's real background + a back button.
    return Scaffold(
      appBar: AppBar(title: Text(s.radarTitle)),
      body: ListenableBuilder(
        listenable: radar,
        builder: (context, _) {
          final ScanStats stats = radar.stats;
          return Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: NovaSpace.maxContentWidth),
              child: ListView(
                padding: const EdgeInsets.all(NovaSpace.xl),
                children: <Widget>[
                  _RadarHeader(s: s),
                  const SizedBox(height: NovaSpace.xl),
                  _SubscriptionBanner(radar: radar, s: s),
                  const SizedBox(height: NovaSpace.lg),
                  _ScanPanel(radar: radar, stats: stats, s: s),
                  const SizedBox(height: NovaSpace.lg),
                  _PortSelector(radar: radar, s: s),
                  const SizedBox(height: NovaSpace.lg),
                  _SourceSelector(radar: radar, s: s),
                  const SizedBox(height: NovaSpace.lg),
                  _ResultsSection(radar: radar, s: s),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RadarHeader extends StatelessWidget {
  const _RadarHeader({required this.s});
  final NovaStrings s;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const NovaEyebrow('Cloudflare scanner'),
        const SizedBox(height: 6),
        Text(s.radarSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: nova.muted)),
      ],
    );
  }
}

/// Connects the Radar to the active Nova subscription so scans export real,
/// importable nodes (stamped into the subscription template and named like the
/// panel) instead of bare `ip:port`.
class _SubscriptionBanner extends StatelessWidget {
  const _SubscriptionBanner({required this.radar, required this.s});
  final RadarController radar;
  final NovaStrings s;

  /// The subscription URL to bind: the active profile if it's a subscription,
  /// otherwise the first subscription profile that carries a URL.
  String? _subUrl(BuildContext context) {
    final profiles = NovaScope.of(context).profiles;
    final active = profiles.active;
    if (active != null &&
        active.isSubscription &&
        (active.subscriptionUrl ?? '').isNotEmpty) {
      return active.subscriptionUrl;
    }
    for (final p in profiles.profiles) {
      if (p.isSubscription && (p.subscriptionUrl ?? '').isNotEmpty) {
        return p.subscriptionUrl;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final cfg = radar.coreConfig;
    final String? subUrl = _subUrl(context);
    final bool busy = radar.isBindingSubscription;

    if (cfg != null) {
      final String flag = coloToFlag(radar.exitColo).trim();
      final String host =
          flag.isEmpty ? cfg.workerHost : '$flag  ${cfg.workerHost}';
      return NovaCard(
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_done_rounded, color: nova.success, size: 20),
            const SizedBox(width: NovaSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(s.subOnTitle,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(host,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: nova.muted)),
                ],
              ),
            ),
            const SizedBox(width: NovaSpace.md),
            if (subUrl != null)
              NovaButton(
                label: s.subRefresh,
                icon: Icons.refresh_rounded,
                variant: NovaButtonVariant.ghost,
                loading: busy,
                onPressed:
                    busy ? null : () => radar.bindSubscription(subUrl),
              ),
          ],
        ),
      );
    }

    return NovaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.cloud_off_rounded, color: nova.muted, size: 20),
              const SizedBox(width: NovaSpace.md),
              Expanded(
                child: Text(s.subOffTitle,
                    style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(s.subOffBody,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: nova.muted)),
          const SizedBox(height: NovaSpace.md),
          NovaButton(
            label: subUrl != null ? s.subUse : s.subNeedProfile,
            icon: Icons.cloud_sync_rounded,
            variant: NovaButtonVariant.secondary,
            expand: true,
            loading: busy,
            onPressed: (subUrl != null && !busy)
                ? () => radar.bindSubscription(subUrl)
                : null,
          ),
          if (radar.bindError != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(s.subError,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: nova.danger)),
          ],
        ],
      ),
    );
  }
}

class _ScanPanel extends StatelessWidget {
  const _ScanPanel({required this.radar, required this.stats, required this.s});
  final RadarController radar;
  final ScanStats stats;
  final NovaStrings s;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final bool scanning = radar.isScanning;
    final List<double> blips = <double>[
      for (int i = 0; i < radar.results.length && i < 12; i++)
        (radar.results[i].ip.hashCode % 1000) / 1000.0,
    ];

    return NovaCard(
      child: Column(
        children: <Widget>[
          Center(child: RadarSweep(active: scanning, blips: blips)),
          const SizedBox(height: NovaSpace.lg),
          if (scanning) ...<Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(NovaRadii.pill),
              child: LinearProgressIndicator(
                value: stats.progress == 0 ? null : stats.progress,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(
                  child: Text(
                    stats.secondPass
                        ? s.deepTesting
                        : '${s.scanning}  ${stats.currentIp}:${stats.currentPort}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: nova.muted),
                  ),
                ),
                Text('${s.eta} ${Fmt.clock(stats.remainingSec)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: nova.muted)),
              ],
            ),
            const SizedBox(height: NovaSpace.md),
          ],
          Row(
            children: <Widget>[
              _Stat(label: s.alive, value: '${stats.aliveCount}', color: nova.success),
              _Stat(label: s.dead, value: '${stats.deadCount}', color: nova.danger),
              _Stat(label: s.scanned, value: '${stats.totalScanned}', color: nova.cyan),
            ],
          ),
          const SizedBox(height: NovaSpace.lg),
          NovaButton(
            label: scanning ? s.stopScan : s.startScan,
            icon: scanning ? Icons.stop_rounded : Icons.play_arrow_rounded,
            variant: scanning ? NovaButtonVariant.danger : NovaButtonVariant.primary,
            expand: true,
            onPressed: scanning ? radar.stopScan : radar.startScan,
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: color)),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: nova.muted)),
        ],
      ),
    );
  }
}

class _PortSelector extends StatelessWidget {
  const _PortSelector({required this.radar, required this.s});
  final RadarController radar;
  final NovaStrings s;

  @override
  Widget build(BuildContext context) {
    return NovaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(s.ports, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: NovaSpace.md),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int port in kAllPorts)
                NovaPill(
                  label: '$port',
                  selected: radar.selectedPorts.contains(port),
                  color: kTlsPorts.contains(port)
                      ? context.nova.cyan
                      : context.nova.violet,
                  onTap: () => radar.togglePort(port),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({required this.radar, required this.s});
  final RadarController radar;
  final NovaStrings s;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return NovaCard(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: NovaSpace.lg),
          childrenPadding: const EdgeInsets.fromLTRB(
              NovaSpace.lg, 0, NovaSpace.lg, NovaSpace.md),
          shape: const RoundedRectangleBorder(borderRadius: NovaRadii.cardR),
          collapsedShape:
              const RoundedRectangleBorder(borderRadius: NovaRadii.cardR),
          leading: Icon(Icons.dns_outlined, color: nova.cyan),
          title: Text(s.sources, style: Theme.of(context).textTheme.titleSmall),
          subtitle: Text(
            '${radar.sources.where((src) => src.enabled).length} / ${radar.sources.length}',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: nova.muted),
          ),
          children: <Widget>[
            for (final src in radar.sources)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: src.enabled,
                onChanged: (v) => radar.toggleSource(src.id, v),
                title: Text(src.name,
                    style: Theme.of(context).textTheme.bodyMedium),
                subtitle: Text(
                  src.type.wire.toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: nova.muted),
                ),
              ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: radar.resetSources,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text(s.reset),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsSection extends StatelessWidget {
  const _ResultsSection({required this.radar, required this.s});
  final RadarController radar;
  final NovaStrings s;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final results = radar.results;

    return NovaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('${s.results} (${results.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (results.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                        ClipboardData(text: radar.exportText()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${results.length} → clipboard')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy_all, size: 16),
                  label: Text(s.copyAll),
                ),
            ],
          ),
          if (results.isNotEmpty) ...<Widget>[
            const SizedBox(height: NovaSpace.sm),
            NovaButton(
              label: radar.isTestingDelays ? s.testing : s.testRealDelay,
              icon: Icons.network_check_rounded,
              variant: NovaButtonVariant.secondary,
              expand: true,
              loading: radar.isTestingDelays,
              onPressed: radar.isTestingDelays ? null : radar.testRealDelays,
            ),
          ],
          const SizedBox(height: NovaSpace.sm),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: NovaSpace.xl),
              child: Center(
                child: Text(s.noResults,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: nova.muted)),
              ),
            )
          else
            for (final r in results)
              _ResultTile(
                result: r,
                realDelayMs: radar.realDelayFor(r.hostPort),
                tested: radar.hasRealDelay(r.hostPort),
              ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.result,
    this.realDelayMs,
    this.tested = false,
  });
  final ScanResult result;

  /// Measured real round-trip delay (ms) once "Test real delay" has run, or
  /// null. [tested] distinguishes "not tested yet" from "tested but failed".
  final int? realDelayMs;
  final bool tested;

  /// The delay we present: the honest real delay when we have it, otherwise the
  /// scan's connect latency as a placeholder.
  int? get _shownMs => tested ? realDelayMs : result.latencyMs;

  Color _latencyColor(BuildContext context) {
    final nova = context.nova;
    final int? ms = _shownMs;
    if (ms == null) return nova.danger; // tested and failed
    if (ms < 200) return nova.success;
    if (ms < 600) return nova.warning;
    return nova.danger;
  }

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final int? ms = _shownMs;
    final String badge = ms == null ? '—' : '$ms ms';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _latencyColor(context).withValues(alpha: 0.14),
              borderRadius: NovaRadii.smR,
              // A subtle ring marks a real-delay-verified entry vs. a raw
              // connect-latency placeholder.
              border: tested
                  ? Border.all(
                      color: _latencyColor(context).withValues(alpha: 0.5))
                  : null,
            ),
            child: Text(badge,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: _latencyColor(context))),
          ),
          const SizedBox(width: NovaSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(result.hostPort,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures()
                          ],
                        )),
                // Stability signal behind the ranking: jitter (latency spread)
                // and packet loss, matching the panel's Radar columns.
                Text(
                  '${NovaStrings.of(context).radarJitter} ${result.jitterMs} ms'
                  ',  ${result.lossPct}% ${NovaStrings.of(context).radarLoss}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: nova.muted),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy, size: 16, color: nova.muted),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result.link));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result.hostPort)),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
