import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/proxy_profile.dart';
import 'singbox/singbox_config.dart';

/// High-level connection lifecycle states surfaced to the UI.
enum ProxyConnectionState { disconnected, connecting, connected, disconnecting, error }

extension ProxyConnectionStateX on ProxyConnectionState {
  bool get isBusy =>
      this == ProxyConnectionState.connecting || this == ProxyConnectionState.disconnecting;
  bool get isActive => this == ProxyConnectionState.connected;
}

/// A point-in-time traffic sample (bytes/second + cumulative bytes).
@immutable
class TrafficStats {
  const TrafficStats({
    this.uplinkBps = 0,
    this.downlinkBps = 0,
    this.uplinkTotal = 0,
    this.downlinkTotal = 0,
  });

  final double uplinkBps;
  final double downlinkBps;
  final int uplinkTotal;
  final int downlinkTotal;

  static const TrafficStats zero = TrafficStats();
}

/// The boundary between Nova Client's UI and the underlying proxy core.
///
/// Nova Client is an optimised Karing-style client: the actual data path is a
/// modified **sing-box** core, bound natively per platform (Android VpnService,
/// the Network Extension on iOS/macOS, a TUN service on desktop). That native
/// binding is intentionally **out of scope** for this milestone — see
/// [SingboxProxyController] for the platform-channel contract it implements.
///
/// Keeping the UI behind this abstraction means screens are built and reviewed
/// against [MockProxyController] today and switch to the real core by swapping
/// a single instance, with no UI changes.
/// A user-facing event the controller wants the UI to announce. Kept as a code
/// so the app shell can render it in the current app language.
enum ProxyNotice {
  /// A manually pinned server was dead, so Nova failed over to the fastest
  /// working one.
  failoverToWorkingServer,
}

abstract class ProxyController extends ChangeNotifier {
  ProxyConnectionState get state;
  TrafficStats get traffic;
  ProxyProfile? get activeProfile;

  /// Human-readable error from the last failed connection attempt, if any.
  String? get lastError;

  /// Transient, user-facing notices the controller wants surfaced (for example,
  /// an automatic failover to a working server). The app shell listens, maps the
  /// code to a localized string, shows a snackbar, then resets it to null. It is
  /// a code (not a string) so the message follows the app language. Kept separate
  /// from [lastError] so an informational message doesn't read as a failure.
  final ValueNotifier<ProxyNotice?> notice = ValueNotifier<ProxyNotice?>(null);

  /// Optional hook the app wires so the controller can persist a profile it had
  /// to mutate on its own, e.g. clearing a dead pinned exit during auto-failover
  /// so the Servers list stops showing the dead server as selected. Without this
  /// the change would live only in memory and the UI would look out of sync.
  Future<void> Function(ProxyProfile profile)? persistProfile;

  /// When the tunnel last became active, used by the dashboard's uptime timer.
  /// Maintained centrally by observing [state] on every notification so the
  /// per-platform implementations don't each have to track it.
  DateTime? _connectedSince;
  DateTime? get connectedSince => _connectedSince;

  @override
  void notifyListeners() {
    if (state.isActive) {
      _connectedSince ??= DateTime.now();
    } else {
      _connectedSince = null;
    }
    super.notifyListeners();
  }

  /// Supplies the current routing/DNS options at connect time. Set once at
  /// startup from the settings controller; the real (sing-box / desktop) hosts
  /// read it when building the config so the Routing and DNS screens actually
  /// take effect. Null falls back to the defaults.
  SingboxRouteOptions Function()? routeOptionsProvider;

  /// The options to build the next config with (defaults when unset).
  SingboxRouteOptions get routeOptions =>
      routeOptionsProvider?.call() ?? const SingboxRouteOptions();

  /// A `HttpClient.findProxy`-style directive for reaching the exit through the
  /// tunnel, or null when no explicit proxying is needed.
  ///
  /// On Android/iOS the data path is a system-wide TUN, so the app's own
  /// `dart:io` requests are already captured and this stays null. On desktop the
  /// core is a local `mixed` inbound that the OS proxy points at, but Dart's
  /// `HttpClient` does not consult the OS proxy, so conn-info (ping/geo) would
  /// otherwise leak out the real interface and report the machine's own IP.
  /// Desktop returns `PROXY 127.0.0.1:<port>` while connected so those probes go
  /// through the exit like every other platform.
  String? get proxyUri => null;

  /// Selects the profile to connect with (does not connect).
  void selectProfile(ProxyProfile? profile);

  /// Re-reads the real tunnel state from the platform (call on app resume so a
  /// still-running tunnel isn't shown as off). Default is a no-op.
  Future<void> syncStatus() async {}

  /// Starts the tunnel for [activeProfile].
  Future<void> connect();

  /// Tears the tunnel down.
  Future<void> disconnect();

  Future<void> toggle() {
    return state.isActive ? disconnect() : connect();
  }

  /// Switches a *live* tunnel to the currently-selected profile/exit without the
  /// user having to toggle off and back on. Select the new profile (or pin a
  /// node) first, then call this: it tears the tunnel down, waits for it to
  /// actually reach `disconnected`, and reconnects through the new exit. If the
  /// tunnel isn't up, it does nothing (the next manual connect uses the new
  /// selection). The wait matters on iOS/macOS: a Network Extension's stop is
  /// asynchronous, and calling start again while it's still stopping is dropped,
  /// which is exactly why switching servers used to silently leave you
  /// disconnected until you tapped connect again.
  Future<void> reconnect() async {
    final bool wasActive =
        state.isActive || state == ProxyConnectionState.connecting;
    if (!wasActive) return;
    await disconnect();
    await _awaitState(
      (ProxyConnectionState s) =>
          s == ProxyConnectionState.disconnected ||
          s == ProxyConnectionState.error,
      timeout: const Duration(seconds: 8),
    );
    await connect();
  }

  /// Completes when [test] passes for the current [state], or after [timeout].
  /// Used by [reconnect] to sequence a stop before the next start.
  Future<void> _awaitState(
    bool Function(ProxyConnectionState) test, {
    required Duration timeout,
  }) async {
    if (test(state)) return;
    final Completer<void> done = Completer<void>();
    void listener() {
      if (test(state) && !done.isCompleted) done.complete();
    }

    addListener(listener);
    try {
      await done.future.timeout(timeout, onTimeout: () {});
    } finally {
      removeListener(listener);
    }
  }
}
