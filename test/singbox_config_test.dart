import 'package:flutter_test/flutter_test.dart';
import 'package:nova_client/src/core/proxy/singbox/proxy_node.dart';
import 'package:nova_client/src/core/proxy/singbox/share_link.dart';
import 'package:nova_client/src/core/proxy/singbox/singbox_config.dart';

void main() {
  group('parseShareLink — VLESS', () {
    test('parses a VLESS WS+TLS link', () {
      final node = parseShareLink(
        'vless://b9c40223-bbc5-4311-89d3-f1ed54bbca86@nova.example.com:443'
        '?encryption=none&security=tls&sni=cdn.example.com&type=ws'
        '&path=%2Fnova&host=cdn.example.com&fp=chrome#Nova%20Node',
      );
      expect(node, isNotNull);
      expect(node!.protocol, NodeProtocol.vless);
      expect(node.server, 'nova.example.com');
      expect(node.port, 443);
      expect(node.uuid, 'b9c40223-bbc5-4311-89d3-f1ed54bbca86');
      expect(node.tls, isTrue);
      expect(node.sni, 'cdn.example.com');
      expect(node.network, 'ws');
      expect(node.wsPath, '/nova');
      expect(node.wsHost, 'cdn.example.com');
      expect(node.fingerprint, 'chrome');
      expect(node.tag, 'Nova Node');
    });
  });

  group('parseShareLink — Trojan', () {
    test('parses a Trojan WS+TLS link', () {
      final node = parseShareLink(
        'trojan://secretpass@tr.example.com:443?security=tls&type=ws&path=/t#TR',
      );
      expect(node, isNotNull);
      expect(node!.protocol, NodeProtocol.trojan);
      expect(node.password, 'secretpass');
      expect(node.server, 'tr.example.com');
      expect(node.port, 443);
      expect(node.tls, isTrue);
      expect(node.network, 'ws');
      expect(node.wsPath, '/t');
    });
  });

  group('parseShareLink — Shadowsocks', () {
    test('parses a SIP002 ss link', () {
      final node = parseShareLink(
        'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@ss.example.com:8388#SS',
      );
      expect(node, isNotNull);
      expect(node!.protocol, NodeProtocol.shadowsocks);
      expect(node.method, 'aes-256-gcm');
      expect(node.password, 'password');
      expect(node.server, 'ss.example.com');
      expect(node.port, 8388);
    });

    test('parses url-safe base64 without padding', () {
      final node = parseShareLink(
        'ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@ss.example.com:8388#SS',
      );
      expect(node, isNotNull);
      expect(node!.method, 'aes-256-gcm');
      expect(node.password, 'password');
    });
  });

  group('parseShareLink — VLESS Reality', () {
    test('captures reality pbk/sid and defaults uTLS fingerprint', () {
      final node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@realsvr.example.com:443'
        '?security=reality&pbk=PUBKEY123&sid=ab12&sni=www.microsoft.com'
        '&flow=xtls-rprx-vision&type=tcp#Reality',
      );
      expect(node, isNotNull);
      expect(node!.protocol, NodeProtocol.vless);
      expect(node.isReality, isTrue);
      expect(node.realityPublicKey, 'PUBKEY123');
      expect(node.realityShortId, 'ab12');
      expect(node.tls, isTrue);
      expect(node.flow, 'xtls-rprx-vision');
      // Reality mandates uTLS; parser defaults fp to chrome when omitted.
      expect(node.fingerprint, 'chrome');

      final proxy = (SingboxConfig.buildMap(node)['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      final tls = proxy['tls'] as Map;
      final reality = tls['reality'] as Map;
      expect(reality['enabled'], isTrue);
      expect(reality['public_key'], 'PUBKEY123');
      expect(reality['short_id'], 'ab12');
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
    });
  });

  group('uTLS default (anti-DPI)', () {
    test('a TLS node without an fp still forges a Chrome uTLS handshake', () {
      // A plain worker VLESS link with security=tls but NO fp param.
      final node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@edge.workers.dev:443'
        '?security=tls&type=ws&path=%2Fnova&host=edge.workers.dev'
        '&sni=edge.workers.dev#Nova',
      );
      expect(node, isNotNull);
      expect(node!.tls, isTrue);

      final proxy = (SingboxConfig.buildMap(node)['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      final tls = proxy['tls'] as Map;
      // uTLS is present and defaults to chrome even though the link had no fp.
      expect((tls['utls'] as Map)['enabled'], isTrue);
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
      // TLS ClientHello fragmentation is on for a plain TLS worker node.
      expect(tls['fragment'], isTrue);
      expect(tls['fragment_fallback_delay'], '500ms');
    });

    test('tlsFragment:false drops the fragment keys (desktop core rejects them)',
        () {
      // The bundled DESKTOP sing-box core FATALs on the outbound `tls.fragment`
      // key ("json: unknown field \"fragment\""), which the user saw as "the
      // core did not come up in time". Desktop builds with tlsFragment:false, so
      // neither key may appear; the uTLS fingerprint must still be present.
      final node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@edge.workers.dev:443'
        '?security=tls&type=ws&path=%2Fnova&host=edge.workers.dev'
        '&sni=edge.workers.dev#Nova',
      )!;
      final proxy = (SingboxConfig.buildMap(
        node,
        options: const SingboxRouteOptions(tlsFragment: false),
      )['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      final tls = proxy['tls'] as Map;
      expect(tls.containsKey('fragment'), isFalse);
      expect(tls.containsKey('fragment_fallback_delay'), isFalse);
      expect((tls['utls'] as Map)['enabled'], isTrue);
    });

    test('tlsFragment:false also drops fragment across a multi-node config', () {
      final nodes = <ProxyNode>[
        parseShareLink(
          'vless://id-a@a.workers.dev:443?security=tls&type=ws&path=/p#A',
        )!,
        parseShareLink(
          'vless://id-b@b.workers.dev:443?security=tls&type=ws&path=/p#B',
        )!,
      ];
      final cfg = SingboxConfig.buildMultiMap(
        nodes,
        options: const SingboxRouteOptions(tlsFragment: false),
      );
      final outbounds = (cfg['outbounds'] as List).cast<Map>();
      for (final o in outbounds.where((o) => o['tls'] != null)) {
        expect((o['tls'] as Map).containsKey('fragment'), isFalse);
      }
    });

    test('Reality nodes are NOT fragmented (handshake already covert)', () {
      final node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@realsvr.example.com:443'
        '?security=reality&pbk=PUBKEY123&sid=ab12&sni=www.microsoft.com'
        '&flow=xtls-rprx-vision&type=tcp#Reality',
      );
      final proxy = (SingboxConfig.buildMap(node!)['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      final tls = proxy['tls'] as Map;
      expect(tls.containsKey('fragment'), isFalse);
      expect(tls.containsKey('reality'), isTrue);
    });
  });

  group('parseShareLink — VMess', () {
    test('parses a base64 vmess link', () {
      // {"v":"2","ps":"VM","add":"vm.example.com","port":"443","id":"uuid-1",
      //  "aid":"0","scy":"auto","net":"ws","path":"/vm","host":"cdn.x","tls":"tls"}
      const b64 =
          'eyJ2IjoiMiIsInBzIjoiVk0iLCJhZGQiOiJ2bS5leGFtcGxlLmNvbSIsInBvcnQiOiI0NDMiLCJpZCI6InV1aWQtMSIsImFpZCI6IjAiLCJzY3kiOiJhdXRvIiwibmV0Ijoid3MiLCJwYXRoIjoiL3ZtIiwiaG9zdCI6ImNkbi54IiwidGxzIjoidGxzIn0=';
      final node = parseShareLink('vmess://$b64');
      expect(node, isNotNull);
      expect(node!.protocol, NodeProtocol.vmess);
      expect(node.server, 'vm.example.com');
      expect(node.port, 443);
      expect(node.uuid, 'uuid-1');
      expect(node.vmessAlterId, 0);
      expect(node.network, 'ws');
      expect(node.wsPath, '/vm');
      expect(node.tls, isTrue);

      final proxy = (SingboxConfig.buildMap(node)['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['type'], 'vmess');
      expect(proxy['uuid'], 'uuid-1');
      expect(proxy['security'], 'auto');
      expect((proxy['transport'] as Map)['type'], 'ws');
    });
  });

  group('parseShareLink — Hysteria2 / TUIC (UDP-native)', () {
    test('parses hysteria2 with salamander obfs', () {
      final node = parseShareLink(
        'hysteria2://p4ss@hy.example.com:443?sni=hy.example.com'
        '&obfs=salamander&obfs-password=xyz#HY',
      );
      expect(node, isNotNull);
      expect(node!.protocol, NodeProtocol.hysteria2);
      expect(node.password, 'p4ss');
      expect(node.tls, isTrue);
      expect(node.obfsType, 'salamander');
      expect(node.protocol.isUdpNative, isTrue);

      final proxy = (SingboxConfig.buildMap(node)['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['type'], 'hysteria2');
      expect(proxy['password'], 'p4ss');
      expect((proxy['obfs'] as Map)['type'], 'salamander');
      expect((proxy['obfs'] as Map)['password'], 'xyz');
      // QUIC-native: no ws/grpc transport.
      expect(proxy.containsKey('transport'), isFalse);
    });

    test('parses tuic with uuid:password', () {
      final node = parseShareLink(
        'tuic://uuid-9:secret@tu.example.com:443?sni=tu.example.com'
        '&congestion_control=bbr&udp_relay_mode=native&alpn=h3#TU',
      );
      expect(node, isNotNull);
      expect(node!.protocol, NodeProtocol.tuic);
      expect(node.uuid, 'uuid-9');
      expect(node.password, 'secret');
      expect(node.congestionControl, 'bbr');
      expect(node.udpRelayMode, 'native');

      final proxy = (SingboxConfig.buildMap(node)['outbounds'] as List)
          .cast<Map>()
          .firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['type'], 'tuic');
      expect(proxy['uuid'], 'uuid-9');
      expect(proxy['congestion_control'], 'bbr');
      expect((proxy['tls'] as Map)['alpn'], contains('h3'));
    });

    test('QUIC is NOT blocked when the exit is UDP-native', () {
      final hy = parseShareLink('hysteria2://p@hy.example.com:443?sni=h#HY')!;
      final rules =
          ((SingboxConfig.buildMap(hy)['route'] as Map)['rules'] as List)
              .cast<Map>();
      final blocksQuic = rules.any(
          (r) => r['protocol'] == 'quic' && r['outbound'] == 'block');
      expect(blocksQuic, isFalse);
    });

    test('QUIC IS blocked for a TCP-only worker (VLESS) exit', () {
      final vless = parseShareLink(
        'vless://id@nova.example.com:443?security=tls&type=ws&path=/p#N',
      )!;
      final rules =
          ((SingboxConfig.buildMap(vless)['route'] as Map)['rules'] as List)
              .cast<Map>();
      final blocksQuic = rules.any(
          (r) => r['protocol'] == 'quic' && r['outbound'] == 'block');
      expect(blocksQuic, isTrue);
    });
  });

  group('parseShareLink — invalid', () {
    test('returns null for unsupported / malformed input', () {
      expect(parseShareLink(''), isNull);
      expect(parseShareLink('https://example.com'), isNull);
      expect(parseShareLink('vless://'), isNull);
      expect(parseShareLink('not a link'), isNull);
    });
  });

  group('SingboxConfig.buildMap', () {
    ProxyNode vlessNode() => parseShareLink(
          'vless://b9c40223-bbc5-4311-89d3-f1ed54bbca86@nova.example.com:443'
          '?security=tls&sni=cdn.example.com&type=ws&path=%2Fnova&host=cdn.example.com#N',
        )!;

    test('produces a TUN inbound with no removed legacy fields', () {
      final cfg = SingboxConfig.buildMap(vlessNode());
      final inbounds = cfg['inbounds'] as List<dynamic>;
      expect(inbounds, hasLength(1));
      final tun = inbounds.first as Map;
      expect(tun['type'], 'tun');
      expect(tun['auto_route'], isTrue);
      // sing-box 1.12 removed inet4_address (use the `address` list);
      // sing-box 1.13 removed the inbound sniff fields (use a rule action).
      expect(tun.containsKey('inet4_address'), isFalse);
      expect(tun['address'], contains('172.19.0.1/30'));
      expect(tun.containsKey('sniff'), isFalse,
          reason: 'legacy inbound sniff field removed in sing-box 1.13');
      expect(tun.containsKey('sniff_override_destination'), isFalse);
      // Sniffing must instead be a route rule action so domain rules still match.
      final routeRules =
          ((cfg['route'] as Map)['rules'] as List<dynamic>).cast<Map>();
      expect(routeRules.any((r) => r['action'] == 'sniff'), isTrue,
          reason: 'sniffing must be a rule action on 1.13');
    });

    test('builds the VLESS outbound with TLS + WS transport', () {
      final cfg = SingboxConfig.buildMap(vlessNode());
      final outbounds = (cfg['outbounds'] as List<dynamic>).cast<Map>();
      final proxy = outbounds.firstWhere((o) => o['tag'] == 'proxy');
      expect(proxy['type'], 'vless');
      expect(proxy['server'], 'nova.example.com');
      expect(proxy['server_port'], 443);
      expect(proxy['uuid'], 'b9c40223-bbc5-4311-89d3-f1ed54bbca86');
      expect((proxy['tls'] as Map)['server_name'], 'cdn.example.com');
      expect((proxy['transport'] as Map)['type'], 'ws');
      expect((proxy['transport'] as Map)['path'], '/nova');

      // direct/block outbounds always present. The legacy 'dns' outbound is
      // gone (removed in sing-box 1.13); DNS is hijacked via a rule action.
      final tags = outbounds.map((o) => o['tag']).toSet();
      expect(tags, containsAll(<String>['proxy', 'direct', 'block']));
      expect(tags, isNot(contains('dns-out')));
      expect(outbounds.any((o) => o['type'] == 'dns'), isFalse);
      final routeRules =
          ((cfg['route'] as Map)['rules'] as List<dynamic>).cast<Map>();
      expect(
        routeRules.any((r) =>
            r['protocol'] == 'dns' && r['action'] == 'hijack-dns'),
        isTrue,
        reason: 'DNS must be hijacked via a rule action, not a dns outbound',
      );
    });

    test('rule mode routes final through the proxy', () {
      final cfg = SingboxConfig.buildMap(vlessNode());
      expect((cfg['route'] as Map)['final'], 'proxy');
    });

    test('direct mode routes final through direct', () {
      final cfg = SingboxConfig.buildMap(
        vlessNode(),
        options: const SingboxRouteOptions(mode: SingboxMode.direct),
      );
      expect((cfg['route'] as Map)['final'], 'direct');
    });

    test('Iran bypass adds geoip/geosite rule-sets', () {
      final cfg = SingboxConfig.buildMap(vlessNode());
      final route = cfg['route'] as Map;
      final ruleSets = (route['rule_set'] as List).cast<Map>();
      final tags = ruleSets.map((r) => r['tag']).toSet();
      expect(tags, containsAll(<String>['geoip-ir', 'geosite-ir']));
    });

    test('localRuleSets uses bundled files, never a remote download', () {
      // Desktop path: a remote rule-set that can\'t be fetched FATALs the core
      // ("the core did not come up in time" in Iran, where the CDN is blocked),
      // so the full config must reference on-disk rule-sets instead.
      final cfg = SingboxConfig.buildMap(
        vlessNode(),
        options: const SingboxRouteOptions(localRuleSets: true),
      );
      final ruleSets = ((cfg['route'] as Map)['rule_set'] as List).cast<Map>();
      expect(ruleSets, isNotEmpty);
      // Every rule-set must be a local file (no startup download that can FATAL).
      expect(ruleSets.every((r) => r['type'] == 'local'), isTrue);
      expect(ruleSets.any((r) => r['type'] == 'remote'), isFalse);
      expect(ruleSets.any((r) => r.containsKey('url')), isFalse);
      // Paths carry the base token the host swaps for the on-disk directory.
      expect(
        ruleSets.every((r) =>
            (r['path'] as String).contains(SingboxConfig.ruleSetBaseToken)),
        isTrue,
      );
    });

    test('build() returns valid JSON', () {
      final json = SingboxConfig.build(vlessNode());
      expect(json, contains('"type": "tun"'));
      expect(json, contains('"tag": "proxy"'));
    });

    test('remote DNS defaults to Google (8.8.8.8), not Cloudflare', () {
      // The worker exit can\'t relay to Cloudflare\'s own 1.1.1.1 (loop
      // protection), so DoH must default to an off-Cloudflare resolver.
      for (final cfg in <Map<String, dynamic>>[
        SingboxConfig.buildMap(vlessNode()),
        SingboxConfig.buildMap(vlessNode(),
            options: const SingboxRouteOptions(lean: true)),
      ]) {
        final servers = ((cfg['dns'] as Map)['servers'] as List).cast<Map>();
        final remote = servers.firstWhere((s) => s['tag'] == 'remote');
        expect(remote['address'], contains('8.8.8.8'));
        expect(remote['address'], isNot(contains('1.1.1.1')));
        // fake-ip stays reverted for now.
        expect((cfg['dns'] as Map).containsKey('fakeip'), isFalse);
      }
    });

    test('lean path uses bundled LOCAL geosite rule-sets (no geoip, no remote)',
        () {
      final cfg = SingboxConfig.buildMap(
        vlessNode(),
        options: const SingboxRouteOptions(lean: true),
      );
      final route = cfg['route'] as Map;
      final ruleSets = (route['rule_set'] as List).cast<Map>();
      // All lean rule-sets are local (bundled), never remote downloads.
      expect(ruleSets, isNotEmpty);
      expect(ruleSets.every((r) => r['type'] == 'local'), isTrue);
      final tags = ruleSets.map((r) => r['tag']).toSet();
      expect(tags, containsAll(<String>['geosite-ir', 'geosite-ads']));
      // geoip can't match fake IPs, so it must not appear on the lean path.
      expect(tags.any((t) => (t as String).startsWith('geoip')), isFalse);
      // Paths carry the base-token the iOS host resolves to the container path.
      expect(
          ruleSets.every(
              (r) => (r['path'] as String).contains(SingboxConfig.ruleSetBaseToken)),
          isTrue);
    });

    test('no platform HTTP proxy (append_http_proxy reverted)', () {
      // Disabled again after build 29; the TUN must carry no platform block.
      final lean = (SingboxConfig.buildMap(
                vlessNode(),
                options: const SingboxRouteOptions(lean: true),
              )['inbounds'] as List)
          .cast<Map>()
          .first;
      expect(lean.containsKey('platform'), isFalse);
    });

    test('lean DNS resolves the proxy server domain directly (no loopback)', () {
      final dns = SingboxConfig.buildMap(
        vlessNode(),
        options: const SingboxRouteOptions(lean: true),
      )['dns'] as Map;
      final rules = (dns['rules'] as List).cast<Map>();
      // The proxy's own server domain resolves via the direct (local) server so
      // bringing the tunnel up doesn't depend on a resolver reached through it.
      expect(
          rules.any((r) => r['server'] == 'local' && r['domain'] != null), isTrue);
    });
  });
}
