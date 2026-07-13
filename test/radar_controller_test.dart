import 'package:flutter_test/flutter_test.dart';
import 'package:nova_client/src/features/radar/radar_controller.dart';

void main() {
  const String host = 'morning-heart-d18c.cornel-pleat1f.workers.dev';
  const String node =
      'vless://e8f57fa7-ecc0-4850-89d1-7814dd585d8c@1.2.3.4:443'
      '?security=tls&type=ws&host=$host&fp=chrome&sni=$host'
      '&path=%2F&encryption=none#node';

  test('bindSubscription parses the body and exposes the core config', () async {
    final radar = RadarController();
    await radar.bindSubscription('https://x/sub', fetch: (_) async => node);

    expect(radar.coreConfig, isNotNull);
    expect(radar.coreConfig!.workerHost, host);
    expect(radar.coreConfig!.template.uuid,
        'e8f57fa7-ecc0-4850-89d1-7814dd585d8c');
    expect(radar.bindError, isNull);
    expect(radar.isBindingSubscription, isFalse);
  });

  test('bindSubscription records an error on an empty subscription', () async {
    final radar = RadarController();
    await radar.bindSubscription('https://x/sub', fetch: (_) async => '');

    expect(radar.coreConfig, isNull);
    expect(radar.bindError, isNotNull);
    expect(radar.isBindingSubscription, isFalse);
  });

  test('applyCoreConfig(null) unbinds back to fallback naming', () async {
    final radar = RadarController();
    await radar.bindSubscription('https://x/sub', fetch: (_) async => node);
    expect(radar.coreConfig, isNotNull);

    radar.applyCoreConfig(null);
    expect(radar.coreConfig, isNull);
  });
}
