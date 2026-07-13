import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_client/src/core/proxy/singbox/nova_naming.dart';
import 'package:nova_client/src/core/proxy/singbox/share_link.dart';
import 'package:nova_client/src/core/proxy/singbox/share_link_builder.dart';

void main() {
  group('flagFromCountry', () {
    test('maps two-letter codes to flag emoji', () {
      expect(flagFromCountry('CA'), '🇨🇦');
      expect(flagFromCountry('DE'), '🇩🇪');
      expect(flagFromCountry('US'), '🇺🇸');
      expect(flagFromCountry('ir'), '🇮🇷'); // case-insensitive
    });

    test('returns empty for invalid input', () {
      expect(flagFromCountry(''), '');
      expect(flagFromCountry('X'), '');
      expect(flagFromCountry('USA'), '');
      expect(flagFromCountry('12'), '');
    });
  });

  group('coloToFlag', () {
    test('maps known colos to flag + trailing space', () {
      expect(coloToFlag('YYZ'), '🇨🇦 '); // Toronto → Canada
      expect(coloToFlag('FRA'), '🇩🇪 '); // Frankfurt → Germany
      expect(coloToFlag('iad'), '🇺🇸 '); // case-insensitive
    });

    test('returns empty for unknown / null colo', () {
      expect(coloToFlag('ZZZ'), '');
      expect(coloToFlag(''), '');
      expect(coloToFlag(null), '');
    });
  });

  group('novaNodeName', () {
    test('matches the core convention {flag} Nova-{id6}{suffix}', () {
      final name = novaNodeName(colo: 'YYZ', rng: Random(1));
      expect(name, matches(RegExp(r'^🇨🇦 Nova-[a-z0-9]{6} ·R$')));
    });

    test('omits the flag for an unknown colo, just like the worker', () {
      final name = novaNodeName(colo: null, rng: Random(1));
      expect(name, matches(RegExp(r'^Nova-[a-z0-9]{6} ·R$')));
    });

    test('id uses only the worker alphabet (lowercase a-z0-9)', () {
      final id = novaNodeId(Random(42));
      expect(id, hasLength(6));
      expect(id, matches(RegExp(r'^[a-z0-9]{6}$')));
    });

    test('honours a custom suffix', () {
      final name = novaNodeName(colo: 'FRA', suffix: '-Radar', rng: Random(7));
      expect(name, matches(RegExp(r'^🇩🇪 Nova-[a-z0-9]{6}-Radar$')));
    });
  });

  group('buildShareLink round-trips a real Nova sub node', () {
    // A node exactly as the live worker emits it (host/sni/fp/path fixed,
    // only address + name vary).
    const link =
        'vless://e8f57fa7-ecc0-4850-89d1-7814dd585d8c@162.159.38.19:2083'
        '?security=tls&type=ws&host=morning-heart-d18c.cornel-pleat1f.workers.dev'
        '&fp=chrome&sni=morning-heart-d18c.cornel-pleat1f.workers.dev'
        '&path=%2F&encryption=none#%F0%9F%87%A8%F0%9F%87%A6%20Nova-wjcf8o';

    test('parse → build → parse preserves every field', () {
      final original = parseShareLink(link)!;
      final rebuilt = parseShareLink(buildShareLink(original))!;

      expect(rebuilt.protocol, original.protocol);
      expect(rebuilt.uuid, original.uuid);
      expect(rebuilt.server, original.server);
      expect(rebuilt.port, original.port);
      expect(rebuilt.tls, original.tls);
      expect(rebuilt.sni, original.sni);
      expect(rebuilt.network, original.network);
      expect(rebuilt.wsHost, original.wsHost);
      expect(rebuilt.wsPath, original.wsPath);
      expect(rebuilt.fingerprint, original.fingerprint);
      expect(rebuilt.tag, original.tag);
      expect(rebuilt.tag, '🇨🇦 Nova-wjcf8o');
    });
  });

  group('stampCleanIp', () {
    test('swaps address/port/name but keeps the template auth + TLS', () {
      final template = parseShareLink(
        'vless://e8f57fa7-ecc0-4850-89d1-7814dd585d8c'
        '@morning-heart-d18c.cornel-pleat1f.workers.dev:443'
        '?security=tls&type=ws&host=morning-heart-d18c.cornel-pleat1f.workers.dev'
        '&fp=chrome&sni=morning-heart-d18c.cornel-pleat1f.workers.dev'
        '&path=%2F&encryption=none#banner',
      )!;

      final stamped = parseShareLink(
        stampCleanIp(
          template: template,
          ip: '104.17.125.27',
          port: 2087,
          name: '🇨🇦 Nova-abc123 ·R',
        ),
      )!;

      // Swapped.
      expect(stamped.server, '104.17.125.27');
      expect(stamped.port, 2087);
      expect(stamped.tag, '🇨🇦 Nova-abc123 ·R');
      // Preserved from the template — this is what makes the node connectable.
      expect(stamped.uuid, 'e8f57fa7-ecc0-4850-89d1-7814dd585d8c');
      expect(stamped.sni, 'morning-heart-d18c.cornel-pleat1f.workers.dev');
      expect(stamped.wsHost, 'morning-heart-d18c.cornel-pleat1f.workers.dev');
      expect(stamped.wsPath, '/');
      expect(stamped.fingerprint, 'chrome');
      expect(stamped.tls, isTrue);
    });
  });
}
