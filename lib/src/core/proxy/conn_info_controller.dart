import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'proxy_controller.dart';

/// Live connection info shown on the dashboard metrics block: the public exit
/// IP, the country it geolocates to, and a round-trip ping. Mirrors the native
/// Android `NovaConnInfo`, which polls roughly every 6 seconds while connected.
@immutable
class ConnInfo {
  const ConnInfo({
    this.reachable = false,
    this.ip,
    this.countryCode,
    this.countryName,
    this.pingMs,
  });

  /// Whether a tiny request actually completes through the tunnel. This is the
  /// honest "is traffic getting through" signal, kept separate from [hasGeo]
  /// because geo providers rate-limit a shared exit IP and a failed lookup must
  /// never be read as a dead tunnel.
  final bool reachable;
  final String? ip;
  final String? countryCode; // ISO-2, e.g. "DE"
  final String? countryName;
  final int? pingMs;

  bool get hasGeo => (countryCode?.isNotEmpty ?? false);

  static const ConnInfo empty = ConnInfo();
}

/// Polls the exit IP/country/ping while the proxy is connected and clears it
/// when disconnected. Best-effort: any network failure leaves the last good
/// value (or empty) and never throws into the UI.
class ConnInfoController extends ChangeNotifier {
  ConnInfoController(this._proxy) {
    _proxy.addListener(_onProxyChanged);
    _client = _makeClient();
  }

  /// A fresh client whose connections are made *after* the tunnel is up. We
  /// rebuild it on each connect so the probe never reuses a keep-alive socket
  /// opened before the tunnel existed — that stale socket is exactly why the
  /// country/ping used to stay blank until a reconnect.
  HttpClient _makeClient() {
    final HttpClient c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(seconds: 3);
    // On desktop the proxy is a local inbound that dart:io won't use on its own,
    // so route these probes through it. On TUN platforms proxyUri is null and
    // this resolves to DIRECT (already tunneled).
    c.findProxy = (_) => _proxy.proxyUri ?? 'DIRECT';
    return c;
  }

  final ProxyController _proxy;

  ConnInfo _info = ConnInfo.empty;
  ConnInfo get info => _info;

  bool _loading = false;
  bool get loading => _loading;

  Timer? _timer;
  bool _wasActive = false;
  late HttpClient _client;

  void _onProxyChanged() {
    final bool active = _proxy.state.isActive;
    if (active && !_wasActive) {
      _start();
    } else if (!active && _wasActive) {
      _stop();
    }
    _wasActive = active;
  }

  void _start() {
    _info = ConnInfo.empty;
    _loading = true;
    notifyListeners();
    // Fresh client so probes use sockets opened through the new tunnel.
    _client.close(force: true);
    _client = _makeClient();
    // The tunnel needs a moment to actually route (urltest picks a node, DNS
    // warms up). Probe right away, then a few quick retries until it's reachable
    // — without this the first reading stayed blank until a manual reconnect.
    _refresh();
    _scheduleWarmup();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) => _refresh());
  }

  void _scheduleWarmup() {
    const List<int> delays = <int>[1500, 3000, 5000, 8000];
    for (final int ms in delays) {
      Timer(Duration(milliseconds: ms), () {
        if (_wasActive && !_info.reachable) _refresh();
      });
    }
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _loading = false;
    _info = ConnInfo.empty;
    notifyListeners();
  }

  Future<void> _refresh() async {
    final (bool reachable, int? probePing) = await _probe();
    final ConnInfo? geo = reachable ? await _fetchGeo() : null;
    _loading = false;
    // Prefer the dedicated probe's round-trip; otherwise fall back to the geo
    // request's round-trip so the ping never reads blank while a country is
    // clearly resolving. A provider that rate-limits the probe endpoint but
    // serves geo would otherwise leave PING empty for the whole session.
    final int? ping = probePing ?? geo?.pingMs ?? _info.pingMs;
    _info = ConnInfo(
      reachable: reachable,
      ip: geo?.ip ?? _info.ip,
      countryCode: geo?.countryCode ?? _info.countryCode,
      countryName: geo?.countryName ?? _info.countryName,
      pingMs: ping,
    );
    notifyListeners();
  }

  /// A tiny `generate_204` request through the tunnel: its completion is the
  /// reachability signal, and its round-trip doubles as a coarse ping. Tries a
  /// couple of non-Cloudflare 204 endpoints in turn (a Nova worker can't relay
  /// to Cloudflare's own endpoints without hitting loop protection, which is
  /// why pinging 1.1.1.1 used to always fail) so one blocked host doesn't drop
  /// the reading entirely.
  Future<(bool, int?)> _probe() async {
    const List<String> urls = <String>[
      'https://www.gstatic.com/generate_204',
      'https://connectivitycheck.gstatic.com/generate_204',
      'https://www.google.com/generate_204',
    ];
    for (final String url in urls) {
      try {
        final Stopwatch sw = Stopwatch()..start();
        final HttpClientRequest req = await _client.getUrl(Uri.parse(url));
        req.followRedirects = false;
        final HttpClientResponse res = await req.close();
        await res.drain<void>();
        sw.stop();
        final bool ok = res.statusCode >= 200 && res.statusCode < 400;
        if (ok) return (true, sw.elapsedMilliseconds);
      } catch (_) {
        // Try the next endpoint.
      }
    }
    return (false, null);
  }

  /// Best-effort exit IP + country over HTTPS, trying providers in turn. The
  /// **non-Cloudflare** provider comes first on purpose: a Nova exit is a
  /// Cloudflare Worker, and a Worker can't relay to Cloudflare's own hosts (loop
  /// protection), so any CF-fronted geo API just fails through the tunnel and the
  /// country stayed blank. Most geo APIs now sit behind Cloudflare (ifconfig.co,
  /// freeipapi, ipwho.is, api.ip.sb, ipapi.co ... all resolve to 104.x/172.6x);
  /// ipinfo.io is the reliable off-Cloudflare one (Google Cloud), so it leads.
  /// The CF ones stay as fallbacks for non-worker exits. The successful request's
  /// round-trip back-fills a coarse ping. Field names differ per provider, so the
  /// parse is tolerant. (ip-api is skipped: cleartext, blocked on a modern SDK.)
  Future<ConnInfo?> _fetchGeo() async {
    const List<String> urls = <String>[
      'https://ipinfo.io/json',
      'https://ifconfig.co/json',
      'https://freeipapi.com/api/json',
      'https://ipwho.is/',
      'https://api.ip.sb/geoip',
    ];
    for (final String url in urls) {
      try {
        final Stopwatch sw = Stopwatch()..start();
        final HttpClientRequest req = await _client.getUrl(Uri.parse(url));
        final HttpClientResponse res = await req.close();
        if (res.statusCode != 200) {
          await res.drain<void>();
          continue;
        }
        final String body = await res.transform(utf8.decoder).join();
        sw.stop();
        final Map<String, dynamic> j = jsonDecode(body) as Map<String, dynamic>;
        final ConnInfo? parsed = _parseGeo(j, sw.elapsedMilliseconds);
        if (parsed != null) return parsed;
      } catch (_) {
        // Try the next provider.
      }
    }
    return null;
  }

  /// Extracts ip / ISO country code / country name from any of the supported
  /// providers, whose JSON keys differ:
  ///   ifconfig.co → ip, country_iso, country
  ///   ipinfo.io   → ip, country (already the ISO code)
  ///   freeipapi   → ipAddress, countryCode, countryName
  ///   ipwho.is / api.ip.sb → ip, country_code, country
  ConnInfo? _parseGeo(Map<String, dynamic> j, int pingMs) {
    final String? ip = (j['ip'] ?? j['ipAddress']) as String?;
    if (ip == null || ip.isEmpty) return null;
    final String? country = j['country'] is String ? j['country'] as String : null;
    // Prefer an explicit ISO field; otherwise a 2-letter "country" is the code.
    String? cc = (j['country_code'] ??
            j['country_iso'] ??
            j['countryCode']) as String?;
    if ((cc == null || cc.isEmpty) && country != null && country.length == 2) {
      cc = country;
    }
    // A full country name, when the provider gives one distinct from the code.
    final String? name = (j['country_name'] ?? j['countryName']) as String? ??
        (country != null && country.length > 2 ? country : null);
    return ConnInfo(
      ip: ip,
      countryCode: cc?.toUpperCase(),
      countryName: name,
      pingMs: pingMs,
    );
  }

  @override
  void dispose() {
    _proxy.removeListener(_onProxyChanged);
    _timer?.cancel();
    _client.close(force: true);
    super.dispose();
  }
}

/// Turns an ISO-3166 alpha-2 code into its flag emoji (regional indicators).
String? countryFlagEmoji(String? iso2) {
  final String? code = iso2?.toUpperCase();
  if (code == null || code.length != 2) return null;
  final int a = code.codeUnitAt(0);
  final int b = code.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return null;
  return String.fromCharCode(0x1F1E6 + (a - 0x41)) +
      String.fromCharCode(0x1F1E6 + (b - 0x41));
}
