import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nova_client/src/core/models/proxy_profile.dart';
import 'package:nova_client/src/core/proxy/desktop_proxy_controller.dart';
import 'package:nova_client/src/core/proxy/proxy_controller.dart';

/// Verifies the desktop core lifecycle end to end on a real Mac: extract the
/// bundled sing-box, run it with a real Nova server, reach the connected state
/// (core serving its Clash API), pass live traffic through the local proxy, and
/// shut down cleanly. The system-proxy step is skipped so the test needs no
/// admin prompt.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A minimal sing-box config using the free Nova server, so startup doesn't
  // wait on remote rule-set downloads. The controller swaps in its own inbound.
  const String freeServerConfig = '''
{
  "log": {"level": "warn"},
  "outbounds": [
    {"type": "vless", "tag": "proxy", "server": "sub.lillio.org", "server_port": 443,
     "uuid": "b90f8c50-b795-4a6d-84dd-d057e87c7f3a",
     "tls": {"enabled": true, "server_name": "sub.lillio.org", "utls": {"enabled": true, "fingerprint": "chrome"}},
     "transport": {"type": "ws", "path": "/", "headers": {"Host": "sub.lillio.org"}}},
    {"type": "direct", "tag": "direct"}
  ],
  "route": {"final": "proxy"}
}
''';

  testWidgets('desktop: connect, pass traffic, disconnect', (tester) async {
    final controller = DesktopProxyController(manageSystemProxy: false);
    controller.selectProfile(ProxyProfile(
      id: 'test',
      name: 'Nova Free',
      kind: ProxyKind.singboxConfig,
      uri: freeServerConfig,
    ));

    await controller.connect();

    // Wait for the connected state (core up).
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
    while (controller.state != ProxyConnectionState.connected &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(controller.state, ProxyConnectionState.connected,
        reason: 'core should reach connected; lastError=${controller.lastError}');

    // Route a request through the local proxy and confirm egress works.
    final HttpClient client = HttpClient()
      ..findProxy = (_) => 'PROXY 127.0.0.1:${controller.socksPort}';
    final HttpClientRequest req =
        await client.getUrl(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'));
    final HttpClientResponse resp = await req.close();
    final String body = await resp.transform(const SystemEncoding().decoder).join();
    client.close(force: true);
    expect(resp.statusCode, 200);
    expect(body.contains('ip='), isTrue, reason: 'should get a trace through the tunnel');

    // Give the traffic poller a tick to read the Clash API.
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(controller.traffic.downlinkTotal, greaterThan(0),
        reason: 'traffic stats should reflect the proxied request');

    await controller.disconnect();
    expect(controller.state, ProxyConnectionState.disconnected);
  });
}
