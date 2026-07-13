import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/proxy_profile.dart';
import 'proxy_controller.dart';
import 'singbox/proxy_node.dart';
import 'singbox/singbox_config.dart';
import 'subscription.dart';

/// The real [ProxyController] backed by a modified **sing-box** core.
///
/// This is the **integration boundary** for the native data path. The Dart side
/// talks to the platform host over a [MethodChannel] (commands) and an
/// [EventChannel] (state + traffic stream); each platform implements the host:
///
///   * **Android** — a foreground `VpnService` that runs the sing-box core and
///     owns the TUN fd.
///   * **iOS / macOS** — a `NEPacketTunnelProvider` Network Extension.
///   * **Windows / Linux** — a privileged TUN helper service.
///
/// ### Channel contract
///
/// MethodChannel `nova.proxy/control`:
///   * `start(configJson: String)` → builds the sing-box config from the
///     active profile and starts the tunnel. Returns when the core is up.
///   * `stop()` → stops the tunnel.
///   * `status()` → returns the current [ProxyConnectionState] name.
///
/// EventChannel `nova.proxy/events` emits maps:
///   * `{ "type": "state", "value": "connected" }`
///   * `{ "type": "traffic", "up": bps, "down": bps, "upTotal": bytes, "downTotal": bytes }`
///   * `{ "type": "error", "message": "text" }`
///
/// Until the native hosts ship, the app wires up [MockProxyController]; flip the
/// instance in `main.dart` to switch over with zero UI changes.
class SingboxProxyController extends ProxyController {
  SingboxProxyController({
    MethodChannel? control,
    EventChannel? events,
  })  : _control = control ?? const MethodChannel('nova.proxy/control'),
        _events = events ?? const EventChannel('nova.proxy/events') {
    _subscribe();
  }

  final MethodChannel _control;
  final EventChannel _events;
  StreamSubscription<dynamic>? _eventSub;

  /// If the tunnel never reports "connected" within this window the start has
  /// effectively hung (e.g. the core stuck initialising), so surface a real
  /// error instead of an endless "Connecting…".
  static const Duration _connectTimeout = Duration(seconds: 30);
  Timer? _watchdog;

  /// Guards the auto-mode self-heal (a single rebuild of a subscription tunnel
  /// that came up but carries no traffic) so a genuinely dead subscription can't
  /// loop reconnecting forever. Reset on each user-initiated connect/disconnect.
  bool _autoHealTried = false;

  /// True only while the self-heal is itself driving a [reconnect], so that
  /// reconnect's internal disconnect/connect don't reset [_autoHealTried] and
  /// re-arm the heal (which would let a dead subscription loop).
  bool _healing = false;

  ProxyConnectionState _state = ProxyConnectionState.disconnected;
  @override
  ProxyConnectionState get state => _state;

  TrafficStats _traffic = TrafficStats.zero;
  @override
  TrafficStats get traffic => _traffic;

  ProxyProfile? _active;
  @override
  ProxyProfile? get activeProfile => _active;

  String? _lastError;
  @override
  String? get lastError => _lastError;

  void _subscribe() {
    _eventSub = _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) {
        _lastError = e.toString();
        _state = ProxyConnectionState.error;
        notifyListeners();
      },
    );
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'state':
        final ProxyConnectionState prev = _state;
        _state = ProxyConnectionState.values.firstWhere(
          (s) => s.name == event['value'],
          orElse: () => _state,
        );
        // Any settled state clears the connect watchdog.
        if (_state != ProxyConnectionState.connecting) {
          _watchdog?.cancel();
          _watchdog = null;
        }
        notifyListeners();
        // Just came up: verify real traffic actually flows. A manually pinned
        // exit fails over to the fastest live server; an auto (subscription)
        // exit whose urltest pool led with a dead node gets one clean rebuild.
        if (_state == ProxyConnectionState.connected &&
            prev != ProxyConnectionState.connected) {
          if (_active?.pinnedNode != null) {
            unawaited(_verifyPinnedConnectivity());
          } else if (_active?.isSubscription ?? false) {
            unawaited(_verifyAutoConnectivity());
          }
        }
      case 'traffic':
        _traffic = TrafficStats(
          uplinkBps: (event['up'] as num?)?.toDouble() ?? 0,
          downlinkBps: (event['down'] as num?)?.toDouble() ?? 0,
          uplinkTotal: (event['upTotal'] as num?)?.toInt() ?? 0,
          downlinkTotal: (event['downTotal'] as num?)?.toInt() ?? 0,
        );
        notifyListeners();
      case 'error':
        _lastError = event['message'] as String?;
        _state = ProxyConnectionState.error;
        notifyListeners();
    }
  }

  @override
  void selectProfile(ProxyProfile? profile) {
    _active = profile;
    notifyListeners();
  }

  /// Re-reads the real tunnel state from the platform. Called on app resume so
  /// the UI reflects a tunnel that's still running (the event stream only fires
  /// on *changes*, so a relaunched app would otherwise show "disconnected").
  @override
  Future<void> syncStatus() async {
    try {
      final String? name = await _control.invokeMethod<String>('status');
      if (name == null) return;
      final ProxyConnectionState s = ProxyConnectionState.values.firstWhere(
        (ProxyConnectionState s) => s.name == name,
        orElse: () => _state,
      );
      if (s != _state) {
        _state = s;
        if (s != ProxyConnectionState.connecting) {
          _watchdog?.cancel();
          _watchdog = null;
        }
        notifyListeners();
      }
    } catch (_) {
      // Best-effort; leave the current state untouched on failure.
    }
  }

  @override
  Future<void> connect() async {
    final ProxyProfile? profile = _active;
    if (profile == null) {
      _lastError = 'No profile selected';
      _state = ProxyConnectionState.error;
      notifyListeners();
      return;
    }
    // A fresh user-initiated connect re-arms the one-shot auto self-heal; the
    // heal's own reconnect keeps [_autoHealTried] set (via [_healing]) so it
    // can't loop.
    if (!_healing) _autoHealTried = false;
    _state = ProxyConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    final String config;
    try {
      config = await _buildSingboxConfig(profile);
    } on FormatException catch (e) {
      _lastError = e.message;
      _state = ProxyConnectionState.error;
      notifyListeners();
      return;
    } catch (e) {
      _lastError = _subscriptionErrorMessage(e);
      _state = ProxyConnectionState.error;
      notifyListeners();
      return;
    }

    try {
      await _control.invokeMethod<void>('start', <String, dynamic>{
        'configJson': config,
        // Bundled rule-set files the lean iOS config references as local
        // rule-sets. The host writes them next to the config in the App Group.
        if (Platform.isIOS) 'ruleSets': await _leanRuleSets(),
      });
      _armWatchdog();
    } catch (e) {
      _lastError = e is PlatformException ? e.message : e.toString();
      _state = ProxyConnectionState.error;
      notifyListeners();
    }
  }

  /// Turns a subscription-fetch failure into something the user can act on. A
  /// timeout or socket error almost always means the subscription URL is being
  /// filtered on this network (common in Iran, where the worker's *.workers.dev
  /// domain is blocked), not that the config itself is broken.
  String _subscriptionErrorMessage(Object e) {
    final String s = e.toString().toLowerCase();
    final bool networky = s.contains('timed out') ||
        s.contains('socketexception') ||
        s.contains('failed host lookup') ||
        s.contains('connection');
    if (networky) {
      return "Couldn't reach your subscription. This network may be blocking "
          'it (common in Iran). Try mobile data or another network, or connect '
          'through a working config first, then refresh.';
    }
    return 'Could not load subscription: $e';
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(_connectTimeout, () {
      if (_state == ProxyConnectionState.connecting) {
        _lastError = 'The tunnel did not come up in time. The server may be '
            'unreachable, try another config or scan a clean IP in Radar.';
        _state = ProxyConnectionState.error;
        notifyListeners();
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _watchdog?.cancel();
    _watchdog = null;
    // A real user disconnect clears the heal guard so the next session can heal
    // again; the heal's own reconnect (which disconnects first) must not.
    if (!_healing) _autoHealTried = false;
    _state = ProxyConnectionState.disconnecting;
    notifyListeners();
    try {
      await _control.invokeMethod<void>('stop');
    } catch (e) {
      _lastError = e is PlatformException ? e.message : e.toString();
      _state = ProxyConnectionState.error;
      notifyListeners();
    }
  }

  /// Translates a [ProxyProfile] into a sing-box config document: parse the
  /// share link into a [ProxyNode], then build the full config (TUN inbound,
  /// DNS, per-protocol outbound, rule-based routing). A profile that already
  /// holds a full sing-box JSON config is passed through unchanged.
  ///
  /// Throws [FormatException] when the link can't be parsed.
  Future<String> _buildSingboxConfig(ProxyProfile profile) async {
    final String trimmed = profile.uri.trim();
    if (profile.kind == ProxyKind.singboxConfig || trimmed.startsWith('{')) {
      return trimmed;
    }
    // Resolves single links directly and subscriptions by fetching + expanding
    // them, so a subscription profile (empty uri, URL in subscriptionUrl) can
    // actually connect instead of failing as an "invalid profile link". A
    // subscription returns its whole node list so the core auto-picks the
    // fastest via a urltest; a single link is just the one node.
    List<ProxyNode> nodes = await resolveProfileNodes(profile);
    if (nodes.isEmpty) {
      throw FormatException(emptyResolveMessage(profile));
    }
    // Honour a manually pinned exit node: route through just that one instead of
    // letting the urltest auto-pick. Falls back to auto if it's no longer in the
    // subscription.
    final String? pin = profile.pinnedNode;
    if (pin != null) {
      for (final ProxyNode n in nodes) {
        if ('${n.server}:${n.port}' == pin) {
          nodes = <ProxyNode>[n];
          break;
        }
      }
    } else if (profile.fastNodes.isNotEmpty) {
      // Auto-select: front-load the nodes the picker measured as fastest so the
      // urltest pool (which takes the first N) is built from good exits, not the
      // subscription's arbitrary first few.
      final Map<String, int> rank = <String, int>{
        for (int i = 0; i < profile.fastNodes.length; i++)
          profile.fastNodes[i]: i,
      };
      nodes = <ProxyNode>[...nodes]..sort((ProxyNode a, ProxyNode b) {
          final int ra = rank['${a.server}:${a.port}'] ?? 1 << 30;
          final int rb = rank['${b.server}:${b.port}'] ?? 1 << 30;
          return ra.compareTo(rb);
        });
    } else if (nodes.length > 1) {
      // First connect with no measured nodes yet: quickly ping-rank a sample so
      // Auto doesn't land on a dead/slow exit (which shows up as "connected but
      // no internet / no country"). Best-effort and time-boxed.
      nodes = await _rankByPing(nodes);
    }
    // iOS runs the core inside a Network Extension with a hard ~50 MB memory
    // cap, so build a lean config there (fewer nodes, normal MTU, rule-sets fed
    // in as bytes) to keep the extension from being OOM-killed mid-connection.
    //
    // Android keeps the full config but must use BUNDLED (local) rule-sets: the
    // remote-rule-set path downloads geosite/geoip .srs from raw.githubusercontent
    // .com on connect, which fails during tunnel bring-up ("no available network
    // interface") and is blocked outright in Iran, so the core never starts. The
    // core shares this app's sandbox, so we extract the .srs to disk and point the
    // config's path token at them, exactly like the desktop core does.
    final SingboxRouteOptions opts = routeOptions.copyWith(
      lean: Platform.isIOS,
      localRuleSets: Platform.isAndroid,
      // Android's VpnService uses the gvisor stack (userspace TCP, clamped MSS),
      // like iOS. The system stack forwards raw IP and doesn't clamp MSS, which
      // the code comment on the inbound documents as dropping large packets on a
      // constrained full-device TUN. Desktop keeps the system stack (its host
      // clamps fine). tlsFragment stays ON (Iran anti-DPI).
      gvisorStack: Platform.isAndroid,
    );
    final String config = nodes.length == 1
        ? SingboxConfig.build(nodes.first, options: opts)
        : SingboxConfig.buildMulti(nodes, options: opts);
    if (Platform.isAndroid) {
      final String base = await _extractRuleSets();
      return config.replaceAll(SingboxConfig.ruleSetBaseToken, base);
    }
    return config;
  }

  /// Writes the bundled `.srs` rule-sets into the app-support dir (once) and
  /// returns their directory, so the Android core can load them from disk
  /// instead of fetching them over the (blocked) network. Only the two shipped
  /// sets (geosite-ir, geosite-ads) are extracted; that's what [localRuleSets]
  /// references.
  Future<String> _extractRuleSets() async {
    final Directory dir = await getApplicationSupportDirectory();
    for (final String file in <String>[
      SingboxConfig.kGeositeIrFile,
      SingboxConfig.kGeositeAdsFile,
    ]) {
      final File out = File('${dir.path}/$file');
      final ByteData data = await rootBundle.load('assets/rulesets/$file');
      final int len = data.lengthInBytes;
      if (!out.existsSync() || out.lengthSync() != len) {
        await out.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, len),
          flush: true,
        );
      }
    }
    return dir.path.replaceAll(r'\', '/');
  }

  /// After coming up on a manually pinned exit, confirm the exit really carries
  /// traffic. A pinned node builds a single-outbound config, so a dead exit still
  /// "connects" (Cloudflare's anycast IP accepts the TCP handshake) while nothing
  /// actually loads. If the probe fails, drop the pin so the urltest auto-picks
  /// the fastest LIVE node, tell the user, and switch. No loop: the cleared pin
  /// means the reconnect won't re-enter this path (auto already self-heals).
  Future<void> _verifyPinnedConnectivity() async {
    final ProxyProfile? profile = _active;
    if (profile == null || profile.pinnedNode == null) return;
    // Let the tunnel settle before probing.
    await Future<void>.delayed(const Duration(seconds: 3));
    // Bail if the user disconnected or switched away in the meantime.
    if (_state != ProxyConnectionState.connected ||
        _active?.pinnedNode != profile.pinnedNode) {
      return;
    }
    if (await _probeInternet()) return; // exit is healthy
    final ProxyProfile cleared = profile.copyWith(pinnedNode: null);
    _active = cleared;
    // Persist the un-pin so the Servers list stops showing the dead exit as the
    // selected one (otherwise the change is in-memory only and the UI drifts).
    await persistProfile?.call(cleared);
    notice.value = ProxyNotice.failoverToWorkingServer;
    await reconnect();
  }

  /// After an auto (subscription) tunnel comes up, confirm traffic really flows.
  /// A multi-node profile builds a `urltest` outbound: the core health-checks the
  /// pool and settles on a live node, but the *initial* pick can be a dead exit,
  /// so the orb goes green while nothing loads (the exact "connected but no
  /// internet" report). We probe for a while first — urltest usually self-corrects
  /// within a few cycles, no rebuild needed — and only if it never gets through do
  /// we rebuild the tunnel ONCE, which re-resolves the pool and restarts urltest
  /// from scratch. Guarded by [_autoHealTried] so a genuinely dead subscription
  /// can't loop; the honest "Verifying…" subtitle keeps the UI truthful meanwhile.
  Future<void> _verifyAutoConnectivity() async {
    final ProxyProfile? profile = _active;
    if (profile == null || !profile.isSubscription || profile.pinnedNode != null) {
      return;
    }
    // Probe periodically over ~18s, giving urltest time to converge on a live
    // node before we consider a heavier rebuild.
    for (int attempt = 0; attempt < 6; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      // Bail if the user disconnected, switched profile, or pinned in between.
      if (_state != ProxyConnectionState.connected ||
          _active?.id != profile.id ||
          _active?.pinnedNode != null) {
        return;
      }
      if (await _probeInternet()) return; // traffic flows — nothing to do
    }
    // Still nothing after ~18s. Rebuild the tunnel once (fresh pool + fresh
    // urltest) unless we've already tried this session.
    if (_autoHealTried) return;
    _autoHealTried = true;
    _healing = true;
    try {
      await reconnect();
    } finally {
      _healing = false;
    }
  }

  /// Fetches a tiny reliability endpoint. On mobile the core runs as a full
  /// device TUN, so the app's own request egresses through the tunnel: a
  /// reachable 204 means the exit genuinely works, a timeout means it's dead.
  Future<bool> _probeInternet() async {
    // NON-Cloudflare 204 endpoints on purpose: the Nova exit is usually a
    // Cloudflare Worker, and a Worker can't relay to Cloudflare's own hosts
    // (loop protection), so cp.cloudflare.com always fails through the tunnel and
    // made this health check read every pinned exit as dead. gstatic/google are
    // off-Cloudflare and resolve to the working v4 path. Mirrors ConnInfo._probe.
    const List<String> urls = <String>[
      'https://www.gstatic.com/generate_204',
      'https://connectivitycheck.gstatic.com/generate_204',
      'https://www.google.com/generate_204',
    ];
    for (int attempt = 0; attempt < 2; attempt++) {
      final HttpClient client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      try {
        for (final String url in urls) {
          try {
            final HttpClientRequest req =
                await client.getUrl(Uri.parse(url));
            req.followRedirects = false;
            final HttpClientResponse resp =
                await req.close().timeout(const Duration(seconds: 5));
            await resp.drain<void>();
            if (resp.statusCode >= 200 && resp.statusCode < 400) return true;
          } catch (_) {
            // Try the next endpoint.
          }
        }
      } finally {
        client.close(force: true);
      }
    }
    return false;
  }

  /// Loads the bundled `.srs` rule-sets the lean iOS config references, keyed by
  /// the filename the host writes into the App Group. Best-effort per file: a
  /// missing asset is skipped rather than aborting the connection.
  Future<Map<String, Uint8List>> _leanRuleSets() async {
    final Map<String, Uint8List> out = <String, Uint8List>{};
    for (final MapEntry<String, String> e
        in SingboxConfig.leanRuleSetAssets.entries) {
      try {
        final ByteData data = await rootBundle.load(e.key);
        out[e.value] =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } catch (_) {
        // Asset unavailable — skip; the rule-set simply won't apply.
      }
    }
    return out;
  }

  /// TCP-pings a sample of nodes (direct, since this runs before the tunnel is
  /// up) and returns them ordered fastest-first, with unreachable ones last. So
  /// the urltest's pool — the first N — is built from good exits.
  Future<List<ProxyNode>> _rankByPing(List<ProxyNode> nodes) async {
    // Bound the work: dedupe by server:port and only probe a sample.
    final Set<String> seen = <String>{};
    final List<ProxyNode> sample = <ProxyNode>[];
    for (final ProxyNode n in nodes) {
      if (seen.add('${n.server}:${n.port}')) sample.add(n);
      if (sample.length >= 30) break;
    }
    final Map<ProxyNode, int> ping = <ProxyNode, int>{};
    await Future.wait(sample.map((ProxyNode n) async {
      final Stopwatch sw = Stopwatch()..start();
      try {
        final Socket s = await Socket.connect(n.server, n.port,
            timeout: const Duration(milliseconds: 1500));
        sw.stop();
        s.destroy();
        ping[n] = sw.elapsedMilliseconds;
      } catch (_) {
        ping[n] = 1 << 30; // unreachable -> sort last
      }
    }));
    final List<ProxyNode> ranked = <ProxyNode>[...sample]
      ..sort((ProxyNode a, ProxyNode b) =>
          (ping[a] ?? 1 << 30).compareTo(ping[b] ?? 1 << 30));
    // Append any nodes we didn't sample so the pool can still grow if needed.
    final Set<ProxyNode> inRanked = ranked.toSet();
    ranked.addAll(nodes.where((ProxyNode n) => !inRanked.contains(n)));
    return ranked;
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }
}
