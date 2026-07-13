import 'dart:convert';

import 'proxy_node.dart';

/// Parses a proxy share link into a [ProxyNode].
///
/// Supports the formats Nova Proxy hands out plus the real-server protocols the
/// bundled sing-box core can run:
///   * `vless://uuid@host:port?security=tls|reality&type=ws&path=..&sni=..&pbk=..&sid=..#name`
///   * `trojan://password@host:port?security=tls&type=ws&path=..#name`
///   * `vmess://base64(json)`  (v2rayN format)
///   * `hysteria2://password@host:port?sni=..&obfs=salamander&obfs-password=..#name` (also `hy2://`)
///   * `tuic://uuid:password@host:port?sni=..&congestion_control=bbr&udp_relay_mode=native#name`
///   * `ss://base64(method:password)@host:port#name`  (SIP002)
///   * `ss://base64(method:password@host:port)#name`  (legacy)
///
/// Returns `null` for unsupported schemes or malformed links rather than
/// throwing, so callers can surface a friendly error.
ProxyNode? parseShareLink(String raw) {
  final String input = raw.trim();
  if (input.isEmpty) return null;

  final int schemeEnd = input.indexOf('://');
  if (schemeEnd < 0) return null;
  final String scheme = input.substring(0, schemeEnd).toLowerCase();

  try {
    return switch (scheme) {
      'vless' => _parseUserInfoLink(input, NodeProtocol.vless),
      'trojan' => _parseUserInfoLink(input, NodeProtocol.trojan),
      'vmess' => _parseVmess(input),
      'hysteria2' || 'hy2' => _parseHysteria2(input),
      'tuic' => _parseTuic(input),
      'ss' => _parseShadowsocks(input),
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// VLESS and Trojan share the same `scheme://credential@host:port?params#name`
/// shape; only the credential field differs (uuid vs password).
ProxyNode? _parseUserInfoLink(String input, NodeProtocol protocol) {
  final Uri uri = Uri.parse(input);
  final String host = uri.host;
  final int port = uri.port;
  if (host.isEmpty || port == 0) return null;

  final String credential = Uri.decodeComponent(uri.userInfo);
  if (credential.isEmpty) return null;

  final Map<String, String> q = uri.queryParameters;
  final String security = (q['security'] ?? '').toLowerCase();
  final bool reality = security == 'reality';
  final bool tls = security == 'tls' || reality || security == 'xtls';
  final String network = _normalizeNetwork(q['type'] ?? 'tcp');
  // Reality's public key + short id ride in pbk/sid. When present the outbound
  // gets a reality (not plain TLS) handshake, and uTLS is required, so default
  // the fingerprint to chrome if the link omits fp.
  final String? pbk = reality ? (q['pbk'] ?? '') : null;

  return ProxyNode(
    protocol: protocol,
    server: host,
    port: port,
    tag: _name(uri, host),
    uuid: protocol == NodeProtocol.vless ? credential : null,
    password: protocol == NodeProtocol.trojan ? credential : null,
    tls: tls,
    sni: q['sni'] ?? q['peer'] ?? (tls ? host : null),
    allowInsecure: q['allowInsecure'] == '1' || q['allow_insecure'] == 'true',
    alpn: _splitAlpn(q['alpn']),
    fingerprint: (q['fp'] ?? '').isNotEmpty
        ? q['fp']
        : (reality ? 'chrome' : null),
    flow: (q['flow'] ?? '').isEmpty ? null : q['flow'],
    network: network,
    wsPath: _carriesPath(network) ? (q['path'] ?? '/') : null,
    wsHost: _carriesPath(network) ? (q['host'] ?? q['sni']) : null,
    grpcServiceName: network == 'grpc' ? (q['serviceName'] ?? q['path'] ?? '') : null,
    realityPublicKey: (pbk != null && pbk.isNotEmpty) ? pbk : null,
    realityShortId: reality ? q['sid'] : null,
  );
}

/// VMess share links are `vmess://` + base64 of a JSON object (the v2rayN
/// format): { v, ps, add, port, id, aid, scy, net, type, host, path, tls, sni,
/// alpn, fp }. Fields are strings even when numeric.
ProxyNode? _parseVmess(String input) {
  final String b64 = input.substring('vmess://'.length).trim();
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(_decodeBase64(b64)) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  String s(String k) => (j[k] ?? '').toString().trim();
  final String host = s('add');
  final int port = int.tryParse(s('port')) ?? 0;
  final String id = s('id');
  if (host.isEmpty || port == 0 || id.isEmpty) return null;

  final String network = _normalizeNetwork(s('net').isEmpty ? 'tcp' : s('net'));
  final bool tls = s('tls').toLowerCase() == 'tls';
  final String sni = s('sni').isNotEmpty ? s('sni') : s('host');
  return ProxyNode(
    protocol: NodeProtocol.vmess,
    server: host,
    port: port,
    tag: s('ps').isEmpty ? host : s('ps'),
    uuid: id,
    vmessAlterId: int.tryParse(s('aid')) ?? 0,
    vmessSecurity: s('scy').isEmpty ? 'auto' : s('scy'),
    tls: tls,
    sni: tls ? (sni.isEmpty ? host : sni) : null,
    alpn: _splitAlpn(s('alpn')),
    fingerprint: s('fp').isEmpty ? null : s('fp'),
    network: network,
    wsPath: _carriesPath(network) ? (s('path').isEmpty ? '/' : s('path')) : null,
    wsHost: _carriesPath(network) ? (s('host').isEmpty ? null : s('host')) : null,
    grpcServiceName: network == 'grpc' ? s('path') : null,
  );
}

/// Hysteria2 (QUIC): `hysteria2://password@host:port?sni=..&insecure=1&
/// obfs=salamander&obfs-password=..#name`. TLS is always on (it's QUIC).
ProxyNode? _parseHysteria2(String input) {
  final Uri uri = Uri.parse(input);
  final String host = uri.host;
  final int port = uri.port == 0 ? 443 : uri.port;
  if (host.isEmpty) return null;
  final String password = Uri.decodeComponent(uri.userInfo);
  final Map<String, String> q = uri.queryParameters;
  final String obfs = (q['obfs'] ?? '').toLowerCase();
  return ProxyNode(
    protocol: NodeProtocol.hysteria2,
    server: host,
    port: port,
    tag: _name(uri, host),
    password: password.isEmpty ? null : password,
    tls: true,
    sni: q['sni'] ?? q['peer'] ?? host,
    allowInsecure: q['insecure'] == '1' || q['allowInsecure'] == '1',
    alpn: _splitAlpn(q['alpn']),
    obfsType: obfs == 'salamander' ? 'salamander' : null,
    obfsPassword: (q['obfs-password'] ?? q['obfs_password']),
  );
}

/// TUIC v5 (QUIC): `tuic://uuid:password@host:port?sni=..&alpn=h3&
/// congestion_control=bbr&udp_relay_mode=native#name`. TLS is always on.
ProxyNode? _parseTuic(String input) {
  final Uri uri = Uri.parse(input);
  final String host = uri.host;
  final int port = uri.port == 0 ? 443 : uri.port;
  if (host.isEmpty) return null;
  final String userInfo = Uri.decodeComponent(uri.userInfo);
  final int colon = userInfo.indexOf(':');
  final String uuid = colon >= 0 ? userInfo.substring(0, colon) : userInfo;
  final String password = colon >= 0 ? userInfo.substring(colon + 1) : '';
  if (uuid.isEmpty) return null;
  final Map<String, String> q = uri.queryParameters;
  return ProxyNode(
    protocol: NodeProtocol.tuic,
    server: host,
    port: port,
    tag: _name(uri, host),
    uuid: uuid,
    password: password,
    tls: true,
    sni: q['sni'] ?? q['peer'] ?? host,
    allowInsecure: q['allow_insecure'] == '1' || q['insecure'] == '1',
    alpn: _splitAlpn(q['alpn']?.isNotEmpty == true ? q['alpn'] : 'h3'),
    congestionControl:
        (q['congestion_control'] ?? '').isEmpty ? 'bbr' : q['congestion_control'],
    udpRelayMode:
        (q['udp_relay_mode'] ?? '').isEmpty ? 'native' : q['udp_relay_mode'],
  );
}

ProxyNode? _parseShadowsocks(String input) {
  // Strip scheme and fragment.
  final int hashIndex = input.indexOf('#');
  final String name = hashIndex >= 0
      ? Uri.decodeComponent(input.substring(hashIndex + 1))
      : '';
  final String body =
      (hashIndex >= 0 ? input.substring(0, hashIndex) : input).substring(5);

  String method;
  String password;
  String host;
  int port;

  final int atIndex = body.lastIndexOf('@');
  if (atIndex >= 0) {
    // SIP002: ss://base64(method:password)@host:port
    final String userPart = body.substring(0, atIndex);
    final String hostPart = body.substring(atIndex + 1);
    final String decoded = _looksBase64(userPart)
        ? _decodeBase64(userPart)
        : Uri.decodeComponent(userPart);
    final int colon = decoded.indexOf(':');
    if (colon < 0) return null;
    method = decoded.substring(0, colon);
    password = decoded.substring(colon + 1);
    final (String h, int p) = _splitHostPort(hostPart);
    host = h;
    port = p;
  } else {
    // Legacy: ss://base64(method:password@host:port)
    final String decoded = _decodeBase64(body);
    final int at = decoded.lastIndexOf('@');
    if (at < 0) return null;
    final int colon = decoded.indexOf(':');
    if (colon < 0 || colon > at) return null;
    method = decoded.substring(0, colon);
    password = decoded.substring(colon + 1, at);
    final (String h, int p) = _splitHostPort(decoded.substring(at + 1));
    host = h;
    port = p;
  }

  if (host.isEmpty || port == 0) return null;
  return ProxyNode(
    protocol: NodeProtocol.shadowsocks,
    server: host,
    port: port,
    tag: name.isEmpty ? host : name,
    method: method,
    password: password,
  );
}

String _name(Uri uri, String fallback) {
  final String fragment = uri.fragment;
  if (fragment.isEmpty) return fallback;
  return Uri.decodeComponent(fragment);
}

(String, int) _splitHostPort(String hostPort) {
  // Drop any trailing query/path the host:port might carry.
  String hp = hostPort;
  final int slash = hp.indexOf('/');
  if (slash >= 0) hp = hp.substring(0, slash);
  final int q = hp.indexOf('?');
  if (q >= 0) hp = hp.substring(0, q);
  final int colon = hp.lastIndexOf(':');
  if (colon < 0) return (hp, 0);
  final int port = int.tryParse(hp.substring(colon + 1)) ?? 0;
  return (hp.substring(0, colon), port);
}

String _normalizeNetwork(String type) {
  final String t = type.toLowerCase();
  return switch (t) {
    'ws' || 'websocket' => 'ws',
    'grpc' => 'grpc',
    'http' || 'h2' => 'http',
    'httpupgrade' => 'httpupgrade',
    // xhttp / SplitHTTP is an Xray-only transport; the sing-box core has no
    // implementation, so we tag it as-is and skip such nodes when building the
    // config (see buildMultiMap) rather than silently mis-building them as tcp.
    'xhttp' || 'splithttp' => 'xhttp',
    _ => 'tcp',
  };
}

/// Transports that carry an HTTP-style `path` + `host` (ws, http/2, httpupgrade).
bool _carriesPath(String network) =>
    network == 'ws' || network == 'http' || network == 'httpupgrade';

List<String> _splitAlpn(String? alpn) {
  if (alpn == null || alpn.isEmpty) return const <String>[];
  return alpn
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

bool _looksBase64(String s) {
  // SIP002 userinfo is base64; a raw "method:password" contains a colon.
  return !s.contains(':');
}

/// Decodes standard or URL-safe base64, tolerating missing padding.
String _decodeBase64(String input) {
  String s = input.replaceAll('-', '+').replaceAll('_', '/');
  final int mod = s.length % 4;
  if (mod != 0) s = s.padRight(s.length + (4 - mod), '=');
  return utf8.decode(base64.decode(s));
}
