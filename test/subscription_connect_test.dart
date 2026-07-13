import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_client/src/core/models/proxy_profile.dart';
import 'package:nova_client/src/core/proxy/singbox/singbox_config.dart';
import 'package:nova_client/src/core/proxy/subscription.dart';

/// Regression test for the "Unsupported or invalid profile link" bug: a
/// subscription profile (empty uri, URL in subscriptionUrl) must resolve to a
/// real connectable node instead of null.
void main() {
  test('subscription profile resolves to a connectable node', () async {
    final profile = ProxyProfile(
      id: 't',
      name: 'Nova',
      kind: ProxyKind.subscription,
      uri: '',
      subscriptionUrl:
          'https://sub.lillio.org/sub?sub=user1&key=f2190e7f987c',
    );

    final node = await resolveProfileNode(profile);

    expect(node, isNotNull, reason: 'subscription should resolve to a node');
    expect(node!.uuid, isNotNull);
    expect(node.server, isNotEmpty);
    expect(node.tls, isTrue);
    // ignore: avoid_print
    print('resolved: ${node.server}:${node.port} uuid=${node.uuid} '
        'ws=${node.wsPath} host=${node.wsHost} sni=${node.sni}');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('subscription expands to many nodes and builds a capped urltest',
      () async {
    final profile = ProxyProfile(
      id: 't',
      name: 'Nova',
      kind: ProxyKind.subscription,
      uri: '',
      subscriptionUrl:
          'https://sub.lillio.org/sub?sub=user1&key=f2190e7f987c',
    );

    final nodes = await resolveProfileNodes(profile);
    expect(nodes.length, greaterThan(1),
        reason: 'a subscription should expand to multiple nodes');

    final Map<String, dynamic> cfg = SingboxConfig.buildMultiMap(nodes);
    final List<dynamic> outs = cfg['outbounds'] as List<dynamic>;
    final Map<String, dynamic> auto = outs.firstWhere(
      (dynamic o) => (o as Map)['tag'] == 'proxy',
    ) as Map<String, dynamic>;

    expect(auto['type'], 'urltest', reason: 'fastest-node auto-selector');
    final int members = (auto['outbounds'] as List<dynamic>).length;
    expect(members, greaterThan(1));
    expect(members, lessThanOrEqualTo(SingboxConfig.kMaxAutoNodes),
        reason: 'capped for the iOS NE memory budget');
    // The rest of the config still targets the `proxy` tag.
    expect((cfg['route'] as Map)['final'], 'proxy');
    // ignore: avoid_print
    print('multi: ${nodes.length} nodes -> urltest of $members, '
        'json ${jsonEncode(cfg).length} bytes');
  }, timeout: const Timeout(Duration(seconds: 30)));

  // The add dialog used to tag profiles purely by the selected pill, so a
  // mismatched kind produced "Unsupported or invalid profile link". Resolution
  // now keys off the actual content, so both mismatches still connect.
  group('content-driven resolution tolerates a wrong kind tag', () {
    const String shareLink =
        'vless://b90f8c50-b795-4a6d-84dd-d057e87c7f3a@104.17.214.82:443'
        '?security=tls&type=ws&path=/&host=sub.lillio.org&sni=sub.lillio.org#n';

    test('a share link mis-tagged as a subscription still parses', () async {
      final profile = ProxyProfile(
        id: 't',
        name: 'x',
        kind: ProxyKind.subscription, // wrong tag on purpose
        uri: '',
        subscriptionUrl: shareLink, // a vless:// link, not an http URL
      );
      final nodes = await resolveProfileNodes(profile);
      expect(nodes.length, 1);
      expect(nodes.first.server, '104.17.214.82');
      expect(nodes.first.uuid, isNotNull);
    });

    test('an http subscription mis-tagged as vless is still fetched', () async {
      final profile = ProxyProfile(
        id: 't',
        name: 'x',
        kind: ProxyKind.vless, // wrong tag on purpose
        uri: 'https://example.com/sub', // an http URL, not a share link
      );
      final nodes = await resolveProfileNodes(
        profile,
        fetch: (Uri url) async => base64.encode(utf8.encode(shareLink)),
      );
      expect(nodes.length, 1);
      expect(nodes.first.server, '104.17.214.82');
    });
  });
}
