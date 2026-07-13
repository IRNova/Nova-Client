import 'package:flutter_test/flutter_test.dart';
import 'package:nova_client/src/core/proxy/singbox/proxy_node.dart';
import 'package:nova_client/src/core/proxy/singbox/singbox_config.dart';

/// The Routing/DNS screens were previously cosmetic. These lock in that
/// SingboxRouteOptions actually changes the generated sing-box config, so the
/// UI toggles now have a real effect.
void main() {
  final ProxyNode node = ProxyNode(
    protocol: NodeProtocol.vless,
    server: '104.17.214.82',
    port: 443,
    uuid: 'b90f8c50-b795-4a6d-84dd-d057e87c7f3a',
    tls: true,
    network: 'ws',
    wsPath: '/?u=abc',
    wsHost: 'sub.lillio.org',
    sni: 'sub.lillio.org',
  );

  test('global mode routes everything through the proxy', () {
    final cfg = SingboxConfig.buildMap(node,
        options: const SingboxRouteOptions(mode: SingboxMode.global));
    expect((cfg['route'] as Map)['final'], 'proxy');
    // No Iran-bypass rule-set in global mode.
    final rules = (cfg['route'] as Map)['rule_set'];
    final bool hasIran = rules != null &&
        (rules as List).any((dynamic r) => (r as Map)['tag'] == 'geoip-ir');
    expect(hasIran, isFalse);
  });

  test('direct mode routes everything direct', () {
    final cfg = SingboxConfig.buildMap(node,
        options: const SingboxRouteOptions(mode: SingboxMode.direct));
    expect((cfg['route'] as Map)['final'], 'direct');
  });

  test('disabling bypassIran drops the Iran rule-set', () {
    final on = SingboxConfig.buildMap(node,
        options: const SingboxRouteOptions(bypassIran: true));
    final off = SingboxConfig.buildMap(node,
        options: const SingboxRouteOptions(bypassIran: false));
    bool hasIran(Map<String, dynamic> c) {
      final rs = (c['route'] as Map)['rule_set'];
      return rs != null &&
          (rs as List).any((dynamic r) => (r as Map)['tag'] == 'geoip-ir');
    }

    expect(hasIran(on), isTrue);
    expect(hasIran(off), isFalse);
  });

  test('proxy server domains resolve via the direct DNS (no startup loopback)',
      () {
    // Regression: the core aborted with "DNS query loopback in
    // transport[remote]" because the proxy's own server domain fell through to
    // the proxy-detoured resolver. It must be pinned to the `local` server.
    final cfg = SingboxConfig.buildMap(node);
    final List<dynamic> rules = (cfg['dns'] as Map)['rules'] as List<dynamic>;
    final Map<String, dynamic> directRule = rules.firstWhere(
      (dynamic r) => (r as Map)['server'] == 'local' && r.containsKey('domain'),
      orElse: () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    final List<dynamic> domains =
        (directRule['domain'] as List<dynamic>? ?? <dynamic>[]);
    expect(domains, contains('sub.lillio.org'),
        reason: 'the proxy server domain must resolve directly');
  });

  test('rule-sets download directly so TUN startup never deadlocks', () {
    // On the iOS TUN path the proxy is not yet reachable while the core is
    // still starting, so a rule_set that downloads through the proxy blocks
    // service.start() forever ("Connecting…" hangs). Downloading them direct
    // breaks that deadlock; the host they fetch from must resolve via local
    // DNS (see the direct-DNS rule) so the fetch itself doesn't need the proxy.
    final cfg = SingboxConfig.buildMap(node,
        options: const SingboxRouteOptions(bypassIran: true));
    final List<dynamic> sets =
        (cfg['route'] as Map)['rule_set'] as List<dynamic>;
    expect(sets, isNotEmpty);
    for (final dynamic rs in sets) {
      expect((rs as Map)['download_detour'], 'direct');
    }

    final List<dynamic> dnsRules = (cfg['dns'] as Map)['rules'] as List<dynamic>;
    final Map<String, dynamic> directRule = dnsRules.firstWhere(
      (dynamic r) => (r as Map)['server'] == 'local' && r.containsKey('domain'),
      orElse: () => <String, dynamic>{},
    ) as Map<String, dynamic>;
    final List<dynamic> directDomains =
        (directRule['domain'] as List<dynamic>? ?? <dynamic>[]);
    expect(directDomains, contains('raw.githubusercontent.com'),
        reason: 'the rule_set host must resolve without the proxy');
  });

  test('DNS choice changes the remote resolver', () {
    final def = SingboxConfig.buildMap(node);
    final quad9 = SingboxConfig.buildMap(node,
        options: const SingboxRouteOptions(dns: '9.9.9.9'));
    String remote(Map<String, dynamic> c) => ((c['dns'] as Map)['servers']
            as List)
        .firstWhere((dynamic s) => (s as Map)['tag'] == 'remote')['address']
        as String;
    // Default is off-Cloudflare (Google), because the CF-Worker exit can't relay
    // to Cloudflare's own 1.1.1.1 (loop protection) so DoH there would fail.
    expect(remote(def), contains('8.8.8.8'));
    expect(remote(def), isNot(contains('1.1.1.1')));
    expect(remote(quad9), contains('9.9.9.9'));
  });
}
