import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../../core/proxy/proxy_controller.dart';
import '../../core/proxy/subscription.dart';
import '../../core/util/format.dart';
import '../../l10n/nova_strings.dart';
import '../../theme/nova_radii.dart';
import '../../theme/nova_semantics.dart';
import '../../theme/nova_theme.dart';
import '../../widgets/nova_components.dart';
import '../../widgets/nova_scope.dart';
import '../../widgets/nova_segmented_tabs.dart';
import '../../widgets/nova_usage_bar_chart.dart';
import '../cloudflare/cloudflare_controller.dart';

/// The Stats tab — session traffic at a glance: a total card with a live
/// throughput chart, per-direction stat cards, and a realtime live section.
/// History is session-scoped (the underlying core doesn't persist long-term
/// usage), so the range tabs widen the live window rather than fabricate days.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _range = 0; // 0 Live, 1 1m, 2 5m, 3 Session
  static const List<int> _windows = <int>[20, 30, 40, 60];

  // Rolling buffer of recent downlink/uplink samples (bytes/sec).
  final Queue<double> _down = Queue<double>();
  final Queue<double> _up = Queue<double>();
  Timer? _ticker;

  ProxyController? _proxyRef;
  ProxyController get _proxy => _proxyRef!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ProxyController proxy = NovaScope.of(context).proxy;
    if (identical(proxy, _proxyRef)) return;
    _proxyRef?.removeListener(_sync);
    _proxyRef = proxy;
    _proxyRef!.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (_proxyRef == null) return;
    if (_proxy.state.isActive) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _sample());
    } else {
      _ticker?.cancel();
      _ticker = null;
      if (_down.isNotEmpty || _up.isNotEmpty) {
        setState(() {
          _down.clear();
          _up.clear();
        });
      }
    }
  }

  void _sample() {
    final t = _proxy.traffic;
    final int cap = _windows.last;
    _down.addLast(t.downlinkBps);
    _up.addLast(t.uplinkBps);
    while (_down.length > cap) {
      _down.removeFirst();
    }
    while (_up.length > cap) {
      _up.removeFirst();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _proxyRef?.removeListener(_sync);
    super.dispose();
  }

  List<double> _tail(Queue<double> q) {
    final int n = _windows[_range];
    final List<double> list = q.toList();
    if (list.length <= n) return list;
    return list.sublist(list.length - n);
  }

  /// Plan usage + expiry, read from the active subscription's
  /// `subscription-userinfo` header. Empty when there's no such data.
  List<Widget> _planCards(BuildContext context, NovaScope scope) {
    final s = NovaStrings.of(context);
    final SubInfo? sub = subInfoFor(scope.profiles.active?.subscriptionUrl);
    if (sub == null) return const <Widget>[];
    String date(DateTime e) => '${e.year}-${e.month.toString().padLeft(2, '0')}'
        '-${e.day.toString().padLeft(2, '0')}';
    return <Widget>[
      const SizedBox(height: 12),
      _StatCard(
        icon: Icons.pie_chart_rounded,
        label: s.statsPlanUsage,
        value: sub.total > 0
            ? '${Fmt.bytes(sub.used)} / ${Fmt.bytes(sub.total)}'
            : Fmt.bytes(sub.used),
        color: context.nova.cyan,
        wide: true,
      ),
      if (sub.expire != null) ...<Widget>[
        const SizedBox(height: 12),
        _StatCard(
          icon: Icons.event_rounded,
          label: s.statsExpires,
          value: date(sub.expire!),
          color: context.nova.violet,
          wide: true,
        ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scope = NovaScope.of(context);
    final s = NovaStrings.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.proxy, scope.cloudflare]),
      builder: (context, _) {
        final proxy = scope.proxy;
        final bool active = proxy.state.isActive;
        final List<double> down = _tail(_down);

        return Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: NovaSpace.maxContentWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: <Widget>[
                Text(s.navStats,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 14),
                NovaSegmentedTabs(
                  compact: true,
                  selected: _range,
                  onChanged: (i) => setState(() => _range = i),
                  segments: <NovaSegment>[
                    NovaSegment(label: s.statsLive),
                    const NovaSegment(label: '1m'),
                    const NovaSegment(label: '5m'),
                    NovaSegment(label: s.statsSession),
                  ],
                ),
                const SizedBox(height: 12),
                _TotalCard(proxy: proxy, samples: down, active: active),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _StatCard(
                        icon: Icons.arrow_downward_rounded,
                        label: s.download,
                        value: Fmt.bytes(proxy.traffic.downlinkTotal),
                        color: context.nova.cyan,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        icon: Icons.arrow_upward_rounded,
                        label: s.upload,
                        value: Fmt.bytes(proxy.traffic.uplinkTotal),
                        color: context.nova.violet,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _StatCard(
                  icon: Icons.swap_vert_rounded,
                  label: s.statsTotalSession,
                  value: Fmt.bytes(proxy.traffic.downlinkTotal +
                      proxy.traffic.uplinkTotal),
                  color: context.nova.indigo,
                  wide: true,
                ),
                ..._planCards(context, scope),
                const SizedBox(height: 12),
                _WorkerUsageCard(cf: scope.cloudflare),
                const SizedBox(height: 12),
                _LiveSection(proxy: proxy, active: active),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.proxy,
    required this.samples,
    required this.active,
  });

  final ProxyController proxy;
  final List<double> samples;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    final text = Theme.of(context).textTheme;
    final int total =
        proxy.traffic.downlinkTotal + proxy.traffic.uplinkTotal;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: nova.surface,
        borderRadius: NovaRadii.heroR,
        border: Border.all(color: nova.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(s.statsSessionTotal,
              style: text.labelSmall
                  ?.copyWith(color: nova.muted, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text(Fmt.bytes(total),
              style: text.displaySmall?.copyWith(
                color: nova.cyan,
                fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 16),
          if (active && samples.isNotEmpty)
            NovaUsageBarChart(values: samples, accent: nova.cyan, height: 120)
          else
            // Idle: a flat "resting" baseline (a muted row of stubs) reads as
            // ready-and-waiting, where an empty box just read as broken.
            Column(
              children: <Widget>[
                Opacity(
                  opacity: 0.4,
                  child: NovaUsageBarChart(
                    values: List<double>.filled(28, 0),
                    accent: nova.muted,
                    height: 92,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  active ? s.statsMeasuring : s.disconnected,
                  style: text.bodySmall?.copyWith(color: nova.muted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: nova.surface,
        borderRadius: NovaRadii.toolR,
        border: Border.all(color: nova.border),
      ),
      child: Row(
        children: <Widget>[
          NovaIconChip(icon: icon, color: color, size: 36, radius: 10),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(value,
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: text.bodySmall?.copyWith(color: nova.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Cloudflare Worker request usage vs the free-plan daily allowance. Shows a
/// usage bar when connected and analytics are available; otherwise a short hint.
class _WorkerUsageCard extends StatelessWidget {
  const _WorkerUsageCard({required this.cf});
  final CloudflareController cf;

  /// Thousands-separated integer (e.g. 12,345) without pulling in intl.
  static String _grouped(int n) {
    final String s = n.toString();
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    final text = Theme.of(context).textTheme;
    final bool connected = cf.phase == CfPhase.connected;
    final int? used = connected ? cf.workerRequestsToday : null;
    final int limit = cf.workerRequestLimit;
    final double frac =
        (used != null && limit > 0) ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final Color bar =
        frac < 0.7 ? nova.success : (frac < 0.9 ? nova.warning : nova.danger);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: nova.surface,
        borderRadius: NovaRadii.toolR,
        border: Border.all(color: nova.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              NovaIconChip(
                  icon: Icons.cloud_rounded,
                  color: nova.indigo,
                  size: 36,
                  radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      connected && used != null
                          ? '${_grouped(used)} / ${_grouped(limit)}'
                          : s.statsWorkerUsage,
                      style: text.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      !connected
                          ? s.statsWorkerNoData
                          : (used == null
                              ? s.statsWorkerUsage
                              : s.statsRequestsToday),
                      style: text.bodySmall?.copyWith(color: nova.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (connected && used != null) ...<Widget>[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(NovaRadii.pill),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 8,
                color: bar,
                backgroundColor: nova.surface2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveSection extends StatelessWidget {
  const _LiveSection({required this.proxy, required this.active});
  final ProxyController proxy;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final s = NovaStrings.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(s.statsLiveLabel,
              style: text.labelMedium?.copyWith(
                color: nova.cyan,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              )),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _LiveTile(
                label: s.statsDown,
                value: active ? Fmt.bps(proxy.traffic.downlinkBps) : '—',
                color: NovaSemantics.connectGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LiveTile(
                label: s.statsUp,
                value: active ? Fmt.bps(proxy.traffic.uplinkBps) : '—',
                color: nova.violet,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LiveTile extends StatelessWidget {
  const _LiveTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

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
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(label.toUpperCase(),
                  style: text.labelSmall?.copyWith(
                      color: nova.muted, letterSpacing: 0.6)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
