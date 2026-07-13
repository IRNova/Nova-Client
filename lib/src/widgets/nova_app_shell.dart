import 'package:flutter/material.dart';

import '../core/proxy/proxy_controller.dart';
import '../features/cloudflare/cloudflare_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/servers/servers_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stats/stats_screen.dart';
import '../l10n/nova_strings.dart';
import '../theme/nova_radii.dart';
import '../theme/nova_theme.dart';
import 'nova_connect_button.dart';
import 'nova_logo.dart';
import 'nova_scope.dart';

/// The top-level navigation scaffold. On narrow (mobile) layouts it shows the
/// signature Nova bottom bar — four tabs (Home · Servers · Stats · Settings)
/// with a floating gradient Connect button overflowing the center. On wide
/// (desktop/tablet) layouts it switches to a vertical rail. Radar, Deploy and
/// Panel are reached as pushed "Tools" routes from the Home screen.
class NovaAppShell extends StatefulWidget {
  const NovaAppShell({super.key, this.startAction});

  /// One-time action picked during onboarding: 'deploy' | 'panel' | 'add'.
  final String? startAction;

  @override
  State<NovaAppShell> createState() => _NovaAppShellState();
}

class _NovaAppShellState extends State<NovaAppShell> {
  int _index = 0;

  /// Bumped every time the Home tab is tapped so the dashboard can snap back to
  /// its Summary segment (tapping Home should always land on Summary, even if
  /// you'd left it on Configs).
  final ValueNotifier<int> _homeReset = ValueNotifier<int>(0);

  /// The proxy controller we're subscribed to for user-facing notices (e.g. an
  /// auto-failover message). Tracked so we can move the listener if it changes.
  ProxyController? _noticeSource;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ProxyController proxy = NovaScope.of(context).proxy;
    if (!identical(proxy, _noticeSource)) {
      _noticeSource?.notice.removeListener(_showNotice);
      _noticeSource = proxy;
      proxy.notice.addListener(_showNotice);
    }
  }

  /// Surfaces a controller notice as a snackbar, then clears it so it doesn't
  /// replay. Runs on the notice ValueNotifier's change.
  void _showNotice() {
    final ProxyNotice? code = _noticeSource?.notice.value;
    if (code == null || !mounted) return;
    final NovaStrings s = NovaStrings.of(context);
    final String message = switch (code) {
      ProxyNotice.failoverToWorkingServer => s.failoverSwitched,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ));
    _noticeSource?.notice.value = null;
  }

  @override
  void dispose() {
    _noticeSource?.notice.removeListener(_showNotice);
    _homeReset.dispose();
    super.dispose();
  }

  /// Handles a nav selection: switch tabs, and when Home is chosen, tell the
  /// dashboard to return to Summary.
  void _select(int i) {
    if (i == 0) _homeReset.value++;
    setState(() => _index = i);
  }

  @override
  void initState() {
    super.initState();
    final String? action = widget.startAction;
    if (action == null) return;
    _index = 1; // Servers/Configs
    if (action == 'deploy' || action == 'panel') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CloudflareScreen()),
        );
      });
    }
  }

  void _toggleConnect() {
    final proxy = NovaScope.of(context).proxy;
    if (proxy.activeProfile == null && !proxy.state.isActive) {
      setState(() => _index = 1); // nudge to Servers to pick one
      return;
    }
    proxy.toggle();
  }

  @override
  Widget build(BuildContext context) {
    final s = NovaStrings.of(context);
    final nova = context.nova;

    // Left-of-center and right-of-center tabs; the connect button sits between.
    final List<_Dest> leftDests = <_Dest>[
      _Dest(Icons.home_outlined, Icons.home_rounded, s.navDashboard),
      _Dest(Icons.dns_outlined, Icons.dns_rounded, s.navServers),
    ];
    final List<_Dest> rightDests = <_Dest>[
      _Dest(Icons.bar_chart_outlined, Icons.bar_chart_rounded, s.navStats),
      _Dest(Icons.tune_outlined, Icons.tune_rounded, s.navSettings),
    ];

    final List<Widget> screens = <Widget>[
      DashboardScreen(resetToSummary: _homeReset),
      const ServersScreen(),
      const StatsScreen(),
      const SettingsScreen(),
    ];

    final Widget body = SafeArea(
      bottom: false,
      child: IndexedStack(index: _index, children: screens),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 760;
        if (wide) {
          return Scaffold(
            body: Row(
              children: <Widget>[
                _NovaRail(
                  index: _index,
                  dests: <_Dest>[...leftDests, ...rightDests],
                  onSelect: _select,
                  onConnect: _toggleConnect,
                ),
                VerticalDivider(width: 1, color: nova.border),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: _NovaBottomBar(
            index: _index,
            leftDests: leftDests,
            rightDests: rightDests,
            onSelect: _select,
            onConnect: _toggleConnect,
          ),
        );
      },
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.activeIcon, this.label);
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The rounded-top bottom bar with the floating connect button straddling its
/// top edge in the center.
class _NovaBottomBar extends StatelessWidget {
  const _NovaBottomBar({
    required this.index,
    required this.leftDests,
    required this.rightDests,
    required this.onSelect,
    required this.onConnect,
  });

  final int index; // 0,1 = left; 2,3 = right
  final List<_Dest> leftDests;
  final List<_Dest> rightDests;
  final ValueChanged<int> onSelect;
  final VoidCallback onConnect;

  static const double _barHeight = 64;
  static const double _protrusion = 24;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final proxy = NovaScope.of(context).proxy;

    return SizedBox(
      height: _barHeight + _protrusion + bottomInset,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          // The bar surface, pinned to the bottom.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _barHeight + bottomInset,
            child: Container(
              decoration: BoxDecoration(
                color: nova.navBg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(26),
                ),
                border: Border(top: BorderSide(color: nova.border)),
              ),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < leftDests.length; i++)
                    Expanded(
                      child: _NavItem(
                        dest: leftDests[i],
                        selected: index == i,
                        onTap: () => onSelect(i),
                      ),
                    ),
                  const Spacer(), // center slot reserved for the connect button
                  for (int i = 0; i < rightDests.length; i++)
                    Expanded(
                      child: _NavItem(
                        dest: rightDests[i],
                        selected: index == i + 2,
                        onTap: () => onSelect(i + 2),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Floating connect button, centered over the bar's top edge.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: ListenableBuilder(
                listenable: proxy,
                builder: (context, _) => NovaConnectButton(
                  state: proxy.state,
                  onTap: onConnect,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final Color color = selected ? nova.cyan : nova.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // A pill highlight behind the active icon (Material-3 style) reads
            // as a deliberate selection state rather than just a color swap.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? nova.cyan.withValues(alpha: 0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(NovaRadii.pill),
              ),
              child: Icon(selected ? dest.activeIcon : dest.icon,
                  color: color, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              dest.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NovaRail extends StatelessWidget {
  const _NovaRail({
    required this.index,
    required this.dests,
    required this.onSelect,
    required this.onConnect,
  });

  final int index;
  final List<_Dest> dests;
  final ValueChanged<int> onSelect;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final proxy = NovaScope.of(context).proxy;
    return Container(
      width: 88,
      color: nova.bgAlt,
      child: SafeArea(
        right: false,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 20),
            const NovaLogoBadge(size: 44),
            const SizedBox(height: 20),
            ListenableBuilder(
              listenable: proxy,
              builder: (context, _) => NovaConnectButton(
                state: proxy.state,
                onTap: onConnect,
                size: 52,
              ),
            ),
            const SizedBox(height: 20),
            for (int i = 0; i < dests.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _RailItem(
                  dest: dests[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.dest,
    required this.selected,
    required this.onTap,
  });

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    final Color color = selected ? nova.cyan : nova.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? nova.cyan.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(14),
          border: selected
              ? Border.all(color: nova.cyan.withValues(alpha: 0.4))
              : null,
        ),
        child: Column(
          children: <Widget>[
            Icon(selected ? dest.activeIcon : dest.icon, color: color),
            const SizedBox(height: 6),
            Text(
              dest.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
