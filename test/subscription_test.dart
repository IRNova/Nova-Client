import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_client/src/core/proxy/singbox/share_link.dart';
import 'package:nova_client/src/core/proxy/singbox/share_link_builder.dart';
import 'package:nova_client/src/core/proxy/subscription.dart';

void main() {
  // Two nodes exactly as the live Nova worker emits them: a free-notice banner
  // (address = worker host) and a real clean-IP node. Both share the template.
  const String workerHost = 'morning-heart-d18c.cornel-pleat1f.workers.dev';
  const String banner =
      'vless://e8f57fa7-ecc0-4850-89d1-7814dd585d8c@$workerHost:443'
      '?security=tls&type=ws&host=$workerHost&fp=chrome&sni=$workerHost'
      '&path=%2F&encryption=none#This%20service%20is%20FREE%20-%20Nova%20Proxy%20Team';
  const String node =
      'vless://e8f57fa7-ecc0-4850-89d1-7814dd585d8c@162.159.38.19:2083'
      '?security=tls&type=ws&host=$workerHost&fp=chrome&sni=$workerHost'
      '&path=%2F&encryption=none#%F0%9F%87%A8%F0%9F%87%A6%20Nova-wjcf8o';
  const String plaintext = '$banner\n$node\n';

  group('parseSubscriptionBody', () {
    test('parses plaintext newline-separated links', () {
      final nodes = parseSubscriptionBody(plaintext);
      expect(nodes, hasLength(2));
      expect(nodes[0].server, workerHost);
      expect(nodes[1].server, '162.159.38.19');
      expect(nodes[1].port, 2083);
    });

    test('decodes a base64 subscription body', () {
      final b64 = base64.encode(utf8.encode(plaintext));
      final nodes = parseSubscriptionBody(b64);
      expect(nodes, hasLength(2));
      expect(nodes[1].uuid, 'e8f57fa7-ecc0-4850-89d1-7814dd585d8c');
    });

    test('skips malformed lines instead of throwing', () {
      final nodes = parseSubscriptionBody('not-a-link\n$node\n#comment');
      expect(nodes, hasLength(1));
      expect(nodes.single.server, '162.159.38.19');
    });
  });

  group('NovaCoreConfig', () {
    test('derives template + worker host from the nodes', () {
      final cfg = NovaCoreConfig.fromNodes(parseSubscriptionBody(plaintext))!;
      expect(cfg.nodes, hasLength(2));
      expect(cfg.workerHost, workerHost);
      expect(cfg.sni, workerHost);
      expect(cfg.template.uuid, 'e8f57fa7-ecc0-4850-89d1-7814dd585d8c');
    });

    test('returns null when there are no usable nodes', () {
      expect(NovaCoreConfig.fromNodes(parseSubscriptionBody('garbage')), isNull);
    });

    test('template stamps a clean IP into a connectable node', () {
      final cfg = NovaCoreConfig.fromNodes(parseSubscriptionBody(plaintext))!;
      final stamped = parseShareLink(
        stampCleanIp(
          template: cfg.template,
          ip: '104.17.125.27',
          port: 2087,
          name: '🇨🇦 Nova-test01 ·R',
        ),
      )!;
      expect(stamped.server, '104.17.125.27');
      expect(stamped.port, 2087);
      expect(stamped.sni, workerHost);
      expect(stamped.uuid, 'e8f57fa7-ecc0-4850-89d1-7814dd585d8c');
    });
  });

  group('parseColo / fetchExitColo', () {
    const String trace =
        'fl=123abc\nh=www.cloudflare.com\nip=1.2.3.4\nts=1.0\n'
        'visit_scheme=https\ncolo=YYZ\nhttp=http/2\n';

    test('parseColo extracts the uppercased datacenter code', () {
      expect(parseColo(trace), 'YYZ');
      expect(parseColo('fl=x\nip=1.2.3.4\n'), '');
      expect(parseColo('colo=fra'), 'FRA');
    });

    test('fetchExitColo returns the colo via the injected fetcher', () async {
      final colo = await fetchExitColo(fetch: (_) async => trace);
      expect(colo, 'YYZ');
    });

    test('fetchExitColo is best-effort and returns empty on failure', () async {
      final colo = await fetchExitColo(fetch: (_) async => throw 'boom');
      expect(colo, '');
    });
  });

  group('fetchCoreConfig', () {
    test('uses the injected fetcher and parses the body', () async {
      Uri? requested;
      final cfg = await fetchCoreConfig(
        'https://example.workers.dev/sub?token=abc&b64',
        fetch: (url) async {
          requested = url;
          return base64.encode(utf8.encode(plaintext));
        },
      );
      expect(requested.toString(),
          'https://example.workers.dev/sub?token=abc&b64');
      expect(cfg, isNotNull);
      expect(cfg!.nodes, hasLength(2));
      expect(cfg.workerHost, workerHost);
    });

    test('returns null on an empty body', () async {
      final cfg = await fetchCoreConfig(
        'https://example.workers.dev/sub',
        fetch: (_) async => '',
      );
      expect(cfg, isNull);
    });
  });
}
