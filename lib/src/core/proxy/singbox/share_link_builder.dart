// The inverse of `share_link.dart`: render a [ProxyNode] back into a share
// link. Nova Client uses this to turn a Radar clean-IP hit into a real,
// importable node by stamping the IP into the subscription's template node,
// instead of emitting a bare `ip:port#name` that no client can connect with.
//
// The VLESS output mirrors the Nova Proxy worker's own link format and
// parameter order (`sourcecode.js`), so a stamped node is structurally
// identical to one the subscription hands out.

import 'proxy_node.dart';

/// Renders [node] as a share link (`vless://…` or `trojan://…`).
///
/// Shadowsocks is intentionally unsupported here: the Nova core only issues
/// VLESS, and Radar templates are always VLESS, so it never arises in practice.
String buildShareLink(ProxyNode node) {
  return switch (node.protocol) {
    NodeProtocol.vless => _buildUserInfoLink(node, 'vless', node.uuid ?? ''),
    NodeProtocol.trojan =>
      _buildUserInfoLink(node, 'trojan', node.password ?? ''),
    // Radar only ever stamps clean Cloudflare IPs into the worker's VLESS
    // template, so these never arise here: a VMess/Hysteria2/TUIC exit is a real
    // server, not a CF IP the scanner would find.
    NodeProtocol.shadowsocks ||
    NodeProtocol.vmess ||
    NodeProtocol.hysteria2 ||
    NodeProtocol.tuic =>
      throw UnsupportedError(
        'Share-link building for ${node.protocol.label} is not supported',
      ),
  };
}

/// Stamps a clean [ip]:[port] and [name] into a subscription [template] node,
/// preserving every auth/TLS/transport field, and returns the resulting share
/// link. This is what a verified Radar IP becomes.
String stampCleanIp({
  required ProxyNode template,
  required String ip,
  required int port,
  required String name,
}) {
  return buildShareLink(template.copyWith(server: ip, port: port, tag: name));
}

String _buildUserInfoLink(ProxyNode node, String scheme, String credential) {
  final List<String> params = <String>[
    'security=${node.tls ? 'tls' : 'none'}',
    'type=${node.network}',
  ];

  if (node.network == 'ws' && (node.wsHost ?? '').isNotEmpty) {
    params.add('host=${Uri.encodeComponent(node.wsHost!)}');
  }
  if ((node.fingerprint ?? '').isNotEmpty) {
    params.add('fp=${Uri.encodeComponent(node.fingerprint!)}');
  }
  if (node.tls && (node.sni ?? '').isNotEmpty) {
    params.add('sni=${Uri.encodeComponent(node.sni!)}');
  }
  if (node.network == 'ws') {
    params.add('path=${Uri.encodeComponent(node.wsPath ?? '/')}');
  }
  if (node.network == 'grpc' && (node.grpcServiceName ?? '').isNotEmpty) {
    params.add('serviceName=${Uri.encodeComponent(node.grpcServiceName!)}');
  }
  // VLESS carries an explicit encryption=none; Trojan does not.
  if (node.protocol == NodeProtocol.vless) {
    params.add('encryption=none');
  }
  if ((node.flow ?? '').isNotEmpty) {
    params.add('flow=${Uri.encodeComponent(node.flow!)}');
  }
  if (node.alpn.isNotEmpty) {
    params.add('alpn=${Uri.encodeComponent(node.alpn.join(','))}');
  }
  if (node.allowInsecure) {
    params.add('allowInsecure=1');
  }

  final String query = params.join('&');
  final String fragment = Uri.encodeComponent(node.tag);
  return '$scheme://${Uri.encodeComponent(credential)}'
      '@${node.server}:${node.port}?$query#$fragment';
}
