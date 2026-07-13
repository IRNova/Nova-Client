import 'dart:io';

import 'package:nova_client/src/core/models/proxy_profile.dart';
import 'package:nova_client/src/core/proxy/singbox/singbox_config.dart';
import 'package:nova_client/src/core/proxy/subscription.dart';

/// Builds the exact sing-box config the iOS/Android app would generate for a
/// subscription (default route options) and writes it to disk, so the core can
/// validate/run it on the desktop for diagnosis.
Future<void> main(List<String> args) async {
  final String url = args.isNotEmpty
      ? args.first
      : 'https://sub.lillio.org/sub?sub=user1&key=f2190e7f987c';
  final profile = ProxyProfile(
    id: 't',
    name: 'Nova',
    kind: ProxyKind.subscription,
    uri: '',
    subscriptionUrl: url,
  );
  final nodes = await resolveProfileNodes(profile);
  // Pass "lean" as a 2nd arg to emit the iOS Network-Extension config.
  final bool lean = args.contains('lean');
  final opts = SingboxRouteOptions(lean: lean);
  final String cfg = nodes.length == 1
      ? SingboxConfig.build(nodes.first, options: opts)
      : SingboxConfig.buildMulti(nodes, options: opts);
  File('/tmp/nova_ios_config.json').writeAsStringSync(cfg);
  stdout.writeln('nodes=${nodes.length} bytes=${cfg.length} '
      '-> /tmp/nova_ios_config.json');
}
