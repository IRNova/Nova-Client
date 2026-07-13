import 'dart:convert';

import 'proxy_node.dart';

/// Routing behaviour, mapping onto the controls on the Routing screen.
enum SingboxMode { rule, global, direct }

class SingboxRouteOptions {
  const SingboxRouteOptions({
    this.mode = SingboxMode.rule,
    this.blockAds = true,
    this.bypassIran = true,
    this.bypassLan = true,
    this.dns = '',
    this.lean = false,
    this.localRuleSets = false,
    this.tlsFragment = true,
    this.gvisorStack = false,
  });

  final SingboxMode mode;
  final bool blockAds;
  final bool bypassIran;
  final bool bypassLan;

  /// Use the bundled LOCAL rule-set files instead of downloading them at
  /// startup. sing-box FATALs when a remote rule-set can't be fetched, and the
  /// CDN it pulls from (raw.githubusercontent.com) is filtered in Iran, so the
  /// desktop core died with "the core did not come up in time". Desktop ships
  /// the .srs files and points at them on disk. Only geosite-ir / geosite-ads
  /// are bundled, so geoip-ir bypass is skipped in this mode (the geosite-ir
  /// domain list still covers Iranian sites). The lean/iOS path already uses
  /// local rule-sets by its own branch; this brings the full path in line.
  final bool localRuleSets;

  /// Memory-lean profile for the iOS Network Extension (hard ~50 MB cap):
  /// fewer auto-select nodes, a normal MTU, and no downloaded rule-sets, so the
  /// extension isn't OOM-killed a few seconds into the connection. Desktop and
  /// Android (roomier memory) leave this off and get the full config.
  final bool lean;

  /// Emit the outbound TLS `fragment` / `fragment_fallback_delay` keys (the
  /// ClientHello fragmentation that splits the handshake so DPI can't match the
  /// SNI in one packet). The mobile cores (iOS 1.12.x, Android 1.13.x) accept
  /// these keys; the bundled DESKTOP core does NOT and FATALs on startup with
  /// "outbounds[..].tls.fragment: json: unknown field", which the user saw as
  /// "the core did not come up in time". Desktop turns this off (the uTLS Chrome
  /// fingerprint still applies); every other path keeps it on.
  final bool tlsFragment;

  /// The upstream resolver IP the remote DNS server points at (DoH). Empty
  /// means Nova's default (Cloudflare 1.1.1.1). Matches the native app's DNS
  /// picker: '' / 1.1.1.1 / 8.8.8.8 / 9.9.9.9 / 94.140.14.14.
  final String dns;

  /// Force the gvisor TUN stack (userspace TCP) with a normal MTU, regardless of
  /// [lean]. The `system` stack forwards raw IP and does NOT clamp MSS, so on a
  /// full-device TUN with a jumbo MTU the app advertises an oversized MSS that
  /// the real 1500-MTU path can't carry: TLS handshakes and bulk downloads get
  /// reset ("ERR_CONNECTION_RESET" / traffic stalls). gvisor terminates TCP in
  /// userspace and decouples the app-side MSS from the network path, which is why
  /// iOS already uses it. Android's VpnService hits the exact same wall, so it
  /// sets this too. Desktop keeps the system stack (its host handles MSS fine).
  final bool gvisorStack;

  SingboxRouteOptions copyWith({
    bool? lean,
    bool? localRuleSets,
    bool? tlsFragment,
    bool? gvisorStack,
  }) =>
      SingboxRouteOptions(
        mode: mode,
        blockAds: blockAds,
        bypassIran: bypassIran,
        bypassLan: bypassLan,
        dns: dns,
        lean: lean ?? this.lean,
        localRuleSets: localRuleSets ?? this.localRuleSets,
        tlsFragment: tlsFragment ?? this.tlsFragment,
        gvisorStack: gvisorStack ?? this.gvisorStack,
      );
}

/// Builds a sing-box configuration document from a [ProxyNode].
///
/// Targets the sing-box 1.8–1.11 schema (TUN inbound + DNS + rule-based route
/// with remote rule-sets). This is exactly the JSON the native core consumes;
/// keeping it in Dart means it is unit-tested and shared across every platform
/// host, with the native side only responsible for running it on the TUN fd.
class SingboxConfig {
  const SingboxConfig._();

  // Iran + ad rule-sets — the de-facto standard sources for sing-box on Iranian
  // networks (used when the matching routing toggles are on).
  static const String _adsRuleSet =
      'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs';
  static const String _geoipIr =
      'https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geoip-ir.srs';
  static const String _geositeIr =
      'https://raw.githubusercontent.com/Chocolate4U/Iran-sing-box-rules/rule-set/geosite-ir.srs';

  /// Returns the config as a pretty-printed JSON string.
  static String build(
    ProxyNode node, {
    SingboxRouteOptions options = const SingboxRouteOptions(),
  }) {
    return const JsonEncoder.withIndent('  ').convert(buildMap(node, options: options));
  }

  /// Returns the config as a map (useful for tests / further mutation).
  static Map<String, dynamic> buildMap(
    ProxyNode node, {
    SingboxRouteOptions options = const SingboxRouteOptions(),
  }) {
    return <String, dynamic>{
      'log': <String, dynamic>{'level': 'warn', 'timestamp': true},
      'dns': _dns(options,
          directDomains: <String>{
            ..._directDomains(<ProxyNode>[node]),
            ..._ruleSetHosts,
            ..._directHosts,
          }),
      'inbounds': <Map<String, dynamic>>[_tunInbound(options)],
      'outbounds': <Map<String, dynamic>>[
        _outbound(node, fragment: options.tlsFragment),
        <String, dynamic>{'type': 'direct', 'tag': 'direct'},
        <String, dynamic>{'type': 'block', 'tag': 'block'},
        // NB: no 'dns' outbound — it was removed in sing-box 1.13 (Android's
        // core). DNS is hijacked to the DNS module via a route rule action
        // instead (see _route), which works on both 1.12 (iOS) and 1.13.
      ],
      'route': _route(options, blockQuic: !node.protocol.isUdpNative),
    };
  }

  /// The most nodes we ever put behind the auto-selector. The iOS Network
  /// Extension runs under a hard ~50 MB memory cap, and every extra outbound is
  /// a live dialer it has to hold; a few dozen of the subscription's nodes is
  /// plenty to find a fast one without risking the extension being killed.
  static const int kMaxAutoNodes = 24;

  /// Like [build], but for a whole subscription: wires every node behind a
  /// `urltest` tagged `proxy` so the core continuously measures latency and
  /// routes through the fastest one. Falls back to the single-node [build] when
  /// only one node is given. The rest of the document (route, DNS) is identical
  /// because the auto-selector keeps the `proxy` tag the rest of the config
  /// already targets.
  static String buildMulti(
    List<ProxyNode> nodes, {
    SingboxRouteOptions options = const SingboxRouteOptions(),
  }) {
    return const JsonEncoder.withIndent('  ')
        .convert(buildMultiMap(nodes, options: options));
  }

  static Map<String, dynamic> buildMultiMap(
    List<ProxyNode> nodes, {
    SingboxRouteOptions options = const SingboxRouteOptions(),
  }) {
    // The lean (iOS) path trims the node pool to stay under the extension's
    // ~50MB memory cap. Fewer idle outbounds (each holds a periodic urltest
    // probe) means more headroom for the throughput burst of a speed test, which
    // is what was pushing the extension over the limit and dropping the tunnel.
    // 12 is still plenty for the urltest to find a fast exit; roomier hosts
    // (desktop/Android) use the full budget.
    final int cap = options.lean ? 12 : kMaxAutoNodes;
    // Drop transports the sing-box core can't carry at all (xhttp / SplitHTTP is
    // Xray only) so they never sit in the urltest pool as dead exits.
    final List<ProxyNode> usable =
        nodes.where((ProxyNode n) => n.network != 'xhttp').toList();
    // gRPC is a softer case: sing-box speaks standard gRPC (a real external gRPC
    // server works), but the Nova worker's gRPC is Xray "gun" framing that
    // sing-box can't talk to, so Nova gRPC nodes fail to connect. We can't tell
    // the two apart, so instead of dropping gRPC we push it to the back: Auto
    // fills its pool with ws/Trojan first (and never opens on a dead gRPC node),
    // while a sub that is *only* gRPC still gets used. Order within each group is
    // preserved, so the caller's ping ranking still holds.
    final List<ProxyNode> ordered = <ProxyNode>[
      ...usable.where((ProxyNode n) => n.network != 'grpc'),
      ...usable.where((ProxyNode n) => n.network == 'grpc'),
    ];
    final List<ProxyNode> picked =
        _dedupe(ordered.isEmpty ? nodes : ordered).take(cap).toList();
    if (picked.length <= 1) {
      return buildMap(
        picked.isEmpty ? nodes.first : picked.first,
        options: options,
      );
    }
    final List<Map<String, dynamic>> nodeOutbounds = <Map<String, dynamic>>[];
    final List<String> tags = <String>[];
    for (int i = 0; i < picked.length; i++) {
      final String tag = 'node-$i';
      tags.add(tag);
      nodeOutbounds
          .add(_outbound(picked[i], tag: tag, fragment: options.tlsFragment));
    }
    return <String, dynamic>{
      'log': <String, dynamic>{'level': 'warn', 'timestamp': true},
      'dns': _dns(options,
          directDomains: <String>{
            ..._directDomains(picked),
            ..._ruleSetHosts,
            ..._directHosts,
          }),
      'inbounds': <Map<String, dynamic>>[_tunInbound(options)],
      'outbounds': <Map<String, dynamic>>[
        // Auto-pick the fastest node and keep tracking it. Every node exits the
        // same Cloudflare worker, so their measured latencies all sit within a
        // few hundred ms of each other. That is exactly why the old 800ms
        // tolerance backfired: no node was ever 800ms faster than another, so the
        // urltest could never move off its initial pick (node-0, an arbitrary
        // first entry), and Auto looked "stuck on a slow server". A tight band
        // lets it settle on the genuinely lowest-latency exit. Connection drops
        // (the reason the band was widened) are already prevented by
        // interrupt_exist_connections: false below, so a small tolerance is safe.
        <String, dynamic>{
          'type': 'urltest',
          'tag': 'proxy',
          'outbounds': tags,
          'url': 'https://www.gstatic.com/generate_204',
          // Re-test every 3 min so a node that degrades is dropped reasonably
          // soon, without hammering the exits.
          'interval': '3m0s',
          // 50ms band: switch to a node only when it is meaningfully faster than
          // the current pick (>50ms), which ignores trivial jitter but still
          // homes in on the lowest-latency exit instead of clinging to node-0.
          'tolerance': 50,
          'idle_timeout': '30m0s',
          // Never tear down live connections when the pick changes: an in-flight
          // download or stream stays on its node instead of being cut.
          'interrupt_exist_connections': false,
        },
        ...nodeOutbounds,
        <String, dynamic>{'type': 'direct', 'tag': 'direct'},
        <String, dynamic>{'type': 'block', 'tag': 'block'},
        // No 'dns' outbound (removed in sing-box 1.13); DNS is hijacked via a
        // route rule action instead (see _route).
      ],
      // If any exit in the pool is UDP-native (Hysteria2/TUIC), let QUIC flow;
      // otherwise (an all-worker pool) keep blocking it so apps fall back to TCP.
      'route': _route(options,
          blockQuic: !picked.any((ProxyNode n) => n.protocol.isUdpNative)),
    };
  }

  /// Drops duplicate endpoints (same server:port:path) so the auto-selector
  /// isn't full of identical hops, keeping the node budget for real variety.
  static List<ProxyNode> _dedupe(List<ProxyNode> nodes) {
    final Set<String> seen = <String>{};
    final List<ProxyNode> out = <ProxyNode>[];
    for (final ProxyNode n in nodes) {
      final String key = '${n.server}:${n.port}:${n.wsPath ?? ''}';
      if (seen.add(key)) out.add(n);
    }
    return out;
  }

  static Map<String, dynamic> _tunInbound(SingboxRouteOptions o) =>
      <String, dynamic>{
        'type': 'tun',
        'tag': 'tun-in',
        'interface_name': 'nova-tun',
        // sing-box 1.12 removed the legacy `inet4_address`/`inet6_address`
        // fields in favour of a single `address` list. Both cores we ship
        // (iOS 1.12.x, Android 1.13.x) are past that cut, so the old field
        // logged "legacy tun address fields ... removed in sing-box 1.12.0";
        // `address` is the current, warning-free form.
        'address': <String>['172.19.0.1/30'],
        // iOS (lean) uses the gvisor stack: the system stack forwards raw IP
        // packets, so on the iOS extension large download packets fragment and
        // get dropped (bulk transfers crawl to ~0 while small requests still
        // work). gvisor terminates TCP in userspace (no fragmentation) and is
        // the standard for the iOS Network Extension. We keep it rather than
        // sing-box's `mixed` stack, which reintroduces that fragmentation risk.
        //
        // MTU: 4064 on the gvisor path (iOS, matching Karing which runs the same
        // core in the same ~50MB NE; and Android) instead of 1500. With gvisor a
        // larger TUN MTU means fewer packets/syscalls per byte, so bulk
        // throughput improves without the fragmentation drops the system stack
        // would hit. Only DESKTOP keeps the system stack + jumbo 9000 MTU: its
        // host clamps MSS correctly, so it survives what a VpnService/NE can't.
        'mtu': (o.lean || o.gvisorStack) ? 4064 : 9000,
        'auto_route': true,
        'strict_route': true,
        'stack': (o.lean || o.gvisorStack) ? 'gvisor' : 'system',
        // Sniffing is NOT set here anymore. sing-box 1.13 removed the
        // inbound-level `sniff`/`sniff_override_destination` fields ("legacy
        // inbound fields ... removed in sing-box 1.13.0"), which was fatal on
        // the Android 1.13 core (inbound[0] failed to initialize, so the tunnel
        // never came up). Sniffing now lives in the route as a `{action: sniff}`
        // rule (see _route); that is the supported form on 1.11+/1.12/1.13.
        //
        // NOTE: platform.http_proxy (advertising a system HTTP proxy via
        // NEProxySettings) was tried in build 29 and is disabled again, it is a
        // prime suspect for build 29's broken browsing (all HTTP/HTTPS was routed
        // to the proxy port; if that listener misbehaves, browsers fail while
        // Telegram, which ignores the system proxy, keeps working). The native
        // openTun handler stays (dormant: isHTTPProxyEnabled() is now false) so
        // re-enabling is a one-line config change once the base path is verified.
      };

  static Map<String, dynamic> _dns(
    SingboxRouteOptions o, {
    Iterable<String> directDomains = const <String>[],
  }) {
    // The resolver for proxied (remote) DNS, over DoH so Iran's DNS tampering
    // can't touch it, reached THROUGH the proxy. IP-based, so it needs no
    // bootstrap resolver.
    //
    // Default is Google (8.8.8.8), NOT Cloudflare (1.1.1.1): the Nova exit is a
    // Cloudflare Worker, and a Worker cannot relay to Cloudflare's own endpoints
    // (loop protection), so a DoH query to 1.1.1.1 through the worker silently
    // fails. With no DNS, only apps that dial hardcoded IPs (Telegram) work
    // while browsers/Instagram can't resolve anything — the exact "only Telegram
    // opens" report. 8.8.8.8 is off-Cloudflare, so the worker can reach it.
    final String remote = o.dns.isEmpty ? '8.8.8.8' : o.dns;
    final List<String> direct = directDomains.toList();

    return <String, dynamic>{
      'servers': <Map<String, dynamic>>[
        <String, dynamic>{
          'tag': 'remote',
          'address': 'https://$remote/dns-query',
          'detour': 'proxy',
        },
        <String, dynamic>{
          'tag': 'local',
          'address': 'https://223.5.5.5/dns-query',
          'detour': 'direct',
        },
        <String, dynamic>{'tag': 'block', 'address': 'rcode://success'},
      ],
      'rules': <Map<String, dynamic>>[
        // The proxy's own server domains MUST resolve directly. Otherwise
        // resolving them falls through to `remote`, which is reached *through*
        // the proxy, which needs them resolved first — sing-box aborts startup
        // with "DNS query loopback in transport[remote]" and nothing connects.
        if (direct.isNotEmpty)
          <String, dynamic>{'domain': direct, 'server': 'local'},
        // These reference rule-sets that _route() defines (remote on the full
        // path, bundled-local on the lean/iOS path), so both can resolve Iran
        // domains for real and drop ads.
        if (o.blockAds && o.mode != SingboxMode.direct)
          <String, dynamic>{'rule_set': 'geosite-ads', 'server': 'block'},
        if (o.bypassIran && o.mode == SingboxMode.rule)
          <String, dynamic>{'rule_set': 'geosite-ir', 'server': 'local'},
      ],
      'final': o.mode == SingboxMode.direct ? 'local' : 'remote',
      'strategy': 'prefer_ipv4',
    };
  }

  static Map<String, dynamic> _outbound(
    ProxyNode n, {
    String tag = 'proxy',
    bool fragment = true,
  }) {
    final Map<String, dynamic> o = <String, dynamic>{
      'type': n.protocol.singboxType,
      'tag': tag,
      'server': n.server,
      'server_port': n.port,
    };
    switch (n.protocol) {
      case NodeProtocol.vless:
        o['uuid'] = n.uuid;
        if (n.flow != null) o['flow'] = n.flow;
      case NodeProtocol.trojan:
        o['password'] = n.password;
      case NodeProtocol.shadowsocks:
        o['method'] = n.method;
        o['password'] = n.password;
      case NodeProtocol.vmess:
        o['uuid'] = n.uuid;
        o['alter_id'] = n.vmessAlterId;
        o['security'] = n.vmessSecurity ?? 'auto';
      case NodeProtocol.hysteria2:
        if (n.password != null) o['password'] = n.password;
        if (n.obfsType != null && n.obfsType!.isNotEmpty) {
          o['obfs'] = <String, dynamic>{
            'type': n.obfsType,
            'password': n.obfsPassword ?? '',
          };
        }
      case NodeProtocol.tuic:
        o['uuid'] = n.uuid;
        o['password'] = n.password ?? '';
        o['congestion_control'] = n.congestionControl ?? 'bbr';
        o['udp_relay_mode'] = n.udpRelayMode ?? 'native';
    }
    if (n.tls) o['tls'] = _tls(n, fragment: fragment);
    // QUIC-native protocols (Hysteria2/TUIC) carry no ws/grpc transport.
    if (!n.protocol.isUdpNative) {
      final Map<String, dynamic>? transport = _transport(n);
      if (transport != null) o['transport'] = transport;
    }
    return o;
  }

  static Map<String, dynamic> _tls(ProxyNode n, {bool fragment = true}) {
    // Always forge a real browser's TLS ClientHello via uTLS, defaulting to
    // Chrome when the link didn't pin a fingerprint. Without this, a plain
    // worker VLESS node hands out Go's stock TLS fingerprint, which Iran's DPI
    // can flag as "not a browser"; a Chrome uTLS handshake blends in with normal
    // HTTPS. This is the client-side half of what Xray-based clients lean on;
    // the other half, ClientHello fragmentation, is applied just below (both the
    // iOS 1.12.x and Android 1.13.x cores now support it).
    // Reality already mandates uTLS, so this just makes every other TLS node
    // match that behaviour.
    final String fingerprint =
        (n.fingerprint != null && n.fingerprint!.isNotEmpty)
            ? n.fingerprint!
            : 'chrome';
    return <String, dynamic>{
      'enabled': true,
      'server_name': n.sni ?? n.server,
      if (n.allowInsecure) 'insecure': true,
      if (n.alpn.isNotEmpty) 'alpn': n.alpn,
      // TLS ClientHello fragmentation (sing-box 1.12+ outbound TLS option, keys
      // `fragment`/`fragment_fallback_delay` — the `tls_fragment` spelling is the
      // route-rule form, not this one). Splits the handshake so Iran's DPI can't
      // match the SNI in a single plaintext packet — the other half of the
      // anti-DPI story alongside the uTLS fingerprint, and the trick Xray-based
      // clients rely on. Not applied to Reality: its handshake already looks like
      // a real TLS session, so fragmenting it would only add latency.
      if (fragment && !n.isReality) ...<String, dynamic>{
        'fragment': true,
        'fragment_fallback_delay': '500ms',
      },
      if (n.isReality)
        'reality': <String, dynamic>{
          'enabled': true,
          'public_key': n.realityPublicKey,
          if (n.realityShortId != null && n.realityShortId!.isNotEmpty)
            'short_id': n.realityShortId,
        },
      'utls': <String, dynamic>{'enabled': true, 'fingerprint': fingerprint},
    };
  }

  static Map<String, dynamic>? _transport(ProxyNode n) {
    switch (n.network) {
      case 'ws':
        return <String, dynamic>{
          'type': 'ws',
          'path': n.wsPath ?? '/',
          if (n.wsHost != null && n.wsHost!.isNotEmpty)
            'headers': <String, dynamic>{'Host': n.wsHost},
        };
      case 'grpc':
        return <String, dynamic>{
          'type': 'grpc',
          'service_name': n.grpcServiceName ?? '',
        };
      case 'http':
        // HTTP/2 transport. sing-box takes `host` as a list and needs TLS/ALPN
        // h2 (handled by the tls block). Previously this fell through to null,
        // so h2 nodes silently built as plain TCP and never connected.
        return <String, dynamic>{
          'type': 'http',
          if (n.wsHost != null && n.wsHost!.isNotEmpty)
            'host': <String>[n.wsHost!],
          'path': n.wsPath ?? '/',
        };
      case 'httpupgrade':
        return <String, dynamic>{
          'type': 'httpupgrade',
          if (n.wsHost != null && n.wsHost!.isNotEmpty) 'host': n.wsHost,
          'path': n.wsPath ?? '/',
        };
      default:
        return null;
    }
  }

  static Map<String, dynamic> _route(SingboxRouteOptions o, {bool blockQuic = true}) {
    final List<Map<String, dynamic>> rules = <Map<String, dynamic>>[
      // Sniff each connection's protocol and domain (TLS SNI, HTTP Host, DNS
      // question) so the domain-based rules below can match. This replaces the
      // inbound-level `sniff` field that sing-box 1.13 removed; the `sniff` rule
      // action is the supported form (valid on 1.11+). It must run first, before
      // the DNS hijack and domain rules that depend on the sniffed name.
      <String, dynamic>{'action': 'sniff'},
      // Hijack sniffed DNS to the DNS module. The old form routed to a 'dns'
      // outbound, which sing-box 1.13 removed; the 'hijack-dns' rule action is
      // the supported replacement (valid on 1.11+/1.12/1.13).
      <String, dynamic>{'protocol': 'dns', 'action': 'hijack-dns'},
      // Nova's own Cloudflare management calls (panel deploy, KV, etc.) must go
      // direct: routing them through the proxy fails because Cloudflare loop-
      // protects requests coming back through a CF-worker exit ("Failed host
      // lookup: api.cloudflare.com" during deploy).
      <String, dynamic>{'domain': _directHosts, 'outbound': 'direct'},
      // vless-over-WS/TLS (the Cloudflare Worker exit) carries TCP only, so QUIC
      // (HTTP/3 over UDP) can't be relayed and just times out — Instagram/
      // YouTube break while TCP apps like Telegram work. Block QUIC so those
      // apps fall back to TCP. But a real Hysteria2/TUIC exit carries UDP end to
      // end, so QUIC must pass through there (that's the whole speed win) — the
      // caller sets [blockQuic] false when any exit is UDP-native.
      if (blockQuic) <String, dynamic>{'protocol': 'quic', 'outbound': 'block'},
    ];
    final List<Map<String, dynamic>> ruleSets = <Map<String, dynamic>>[];

    // Lean (iOS) path: use BUNDLED (local) geosite rule-sets instead of the
    // remote ones the full path downloads — no startup fetch, and small enough
    // for the extension's memory budget. Domain-based only (geoip is skipped:
    // it can't match the fake IPs the lean DNS issues). Iran domains go direct
    // (faster, and off the worker), ads are blocked, everything else proxied.
    if (o.lean) {
      final List<Map<String, dynamic>> leanRuleSets = <Map<String, dynamic>>[];
      if (o.bypassLan && o.mode != SingboxMode.direct) {
        rules.add(<String, dynamic>{'ip_is_private': true, 'outbound': 'direct'});
      }
      if (o.blockAds && o.mode != SingboxMode.direct) {
        rules.add(<String, dynamic>{'rule_set': 'geosite-ads', 'outbound': 'block'});
        leanRuleSets.add(_localRuleSet('geosite-ads', kGeositeAdsFile));
      }
      if (o.bypassIran && o.mode == SingboxMode.rule) {
        rules.add(<String, dynamic>{'rule_set': 'geosite-ir', 'outbound': 'direct'});
        leanRuleSets.add(_localRuleSet('geosite-ir', kGeositeIrFile));
      }
      return <String, dynamic>{
        'rules': rules,
        if (leanRuleSets.isNotEmpty) 'rule_set': leanRuleSets,
        'final': o.mode == SingboxMode.direct ? 'direct' : 'proxy',
        'auto_detect_interface': true,
      };
    }

    // Adds the ad-block rule-set, local (bundled) or remote per [o.localRuleSets].
    void addAds() {
      rules.add(<String, dynamic>{'rule_set': 'geosite-ads', 'outbound': 'block'});
      ruleSets.add(o.localRuleSets
          ? _localRuleSet('geosite-ads', kGeositeAdsFile)
          : _remoteRuleSet('geosite-ads', _adsRuleSet));
    }

    if (o.mode == SingboxMode.rule) {
      if (o.bypassLan) {
        rules.add(<String, dynamic>{'ip_is_private': true, 'outbound': 'direct'});
      }
      if (o.blockAds) addAds();
      if (o.bypassIran) {
        if (o.localRuleSets) {
          // geoip-ir isn't bundled; bypass Iran by domain only (the geosite-ir
          // list covers Iranian sites) so nothing has to download at startup.
          rules.add(
              <String, dynamic>{'rule_set': 'geosite-ir', 'outbound': 'direct'});
          ruleSets.add(_localRuleSet('geosite-ir', kGeositeIrFile));
        } else {
          rules.add(<String, dynamic>{
            'rule_set': <String>['geoip-ir', 'geosite-ir'],
            'outbound': 'direct',
          });
          ruleSets.add(_remoteRuleSet('geoip-ir', _geoipIr));
          ruleSets.add(_remoteRuleSet('geosite-ir', _geositeIr));
        }
      }
    } else if (o.mode == SingboxMode.global) {
      if (o.bypassLan) {
        rules.add(<String, dynamic>{'ip_is_private': true, 'outbound': 'direct'});
      }
      if (o.blockAds) addAds();
    }

    final String finalOutbound =
        o.mode == SingboxMode.direct ? 'direct' : 'proxy';

    return <String, dynamic>{
      'rules': rules,
      if (ruleSets.isNotEmpty) 'rule_set': ruleSets,
      'final': finalOutbound,
      'auto_detect_interface': true,
    };
  }

  /// The hosts the remote rule-sets are fetched from. They resolve via the
  /// direct DNS (see [_dns]) so the download never waits on the proxy.
  static const List<String> _ruleSetHosts = <String>['raw.githubusercontent.com'];

  /// Nova's own Cloudflare management endpoints. Resolved via direct DNS and
  /// routed direct (see [_route]) so panel deploy / KV calls work while the
  /// tunnel is up instead of failing a host lookup.
  static const List<String> _directHosts = <String>[
    'api.cloudflare.com',
    'dash.cloudflare.com',
  ];

  /// Placeholder in local rule-set paths, swapped for the real App Group
  /// container path by the iOS host (NovaProxyHost) before the config is written,
  /// so the extension reads the bundled `.srs` files from a valid absolute path.
  static const String ruleSetBaseToken = '__NOVA_BASE__';

  static const String kGeositeIrFile = 'geosite-ir.srs';
  static const String kGeositeAdsFile = 'geosite-ads.srs';

  /// Bundled asset path -> filename the host writes into the container. The iOS
  /// proxy controller ships exactly these on the lean path so the local
  /// rule-sets below resolve. Domain-based (geosite) only: geoip can't match the
  /// fake IPs the lean DNS hands out, so a geoip rule-set would never fire.
  static const Map<String, String> leanRuleSetAssets = <String, String>{
    'assets/rulesets/geosite-ir.srs': kGeositeIrFile,
    'assets/rulesets/geosite-ads.srs': kGeositeAdsFile,
  };

  static Map<String, dynamic> _localRuleSet(String tag, String fileName) =>
      <String, dynamic>{
        'type': 'local',
        'tag': tag,
        'format': 'binary',
        'path': '$ruleSetBaseToken/$fileName',
      };

  static Map<String, dynamic> _remoteRuleSet(String tag, String url) =>
      <String, dynamic>{
        'type': 'remote',
        'tag': tag,
        'format': 'binary',
        'url': url,
        // Download directly, not through `proxy`. On the iOS/Android TUN path
        // the proxy isn't ready while the core is still starting, so a proxied
        // rule-set fetch deadlocks service start and the tunnel hangs on
        // "Connecting". Direct + direct-DNS resolution is self-contained.
        'download_detour': 'direct',
      };

  /// The server/SNI/WS-host domains the proxy outbounds dial. These must resolve
  /// via the direct DNS so bringing the proxy up doesn't depend on a resolver
  /// that is itself reached through the proxy (the startup DNS loop). IP
  /// literals are skipped — they need no resolution.
  static List<String> _directDomains(List<ProxyNode> nodes) {
    final Set<String> out = <String>{};
    for (final ProxyNode n in nodes) {
      for (final String? d in <String?>[n.server, n.sni, n.wsHost]) {
        if (d != null && d.isNotEmpty && !_isIpLiteral(d)) out.add(d);
      }
    }
    return out.toList();
  }

  static bool _isIpLiteral(String host) {
    if (host.contains(':')) return true; // IPv6
    final List<String> parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((String p) {
      final int? v = int.tryParse(p);
      return v != null && v >= 0 && v <= 255;
    });
  }
}
