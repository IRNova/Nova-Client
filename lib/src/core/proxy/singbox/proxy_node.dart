/// A single proxy node parsed from a share link.
///
/// This is the protocol-agnostic intermediate representation the sing-box
/// config builder turns into an outbound. Nova Proxy's own nodes are VLESS /
/// Trojan / Shadowsocks over WS/gRPC + TLS, but the bundled sing-box core also
/// runs VMess, Hysteria2, TUIC and VLESS-Reality — used when a subscription
/// points at a real server (not just the Cloudflare Worker), which is the path
/// to real UDP/QUIC and higher speed.
enum NodeProtocol { vless, trojan, shadowsocks, vmess, hysteria2, tuic }

extension NodeProtocolName on NodeProtocol {
  /// The sing-box outbound `type` for this protocol.
  String get singboxType => switch (this) {
        NodeProtocol.vless => 'vless',
        NodeProtocol.trojan => 'trojan',
        NodeProtocol.shadowsocks => 'shadowsocks',
        NodeProtocol.vmess => 'vmess',
        NodeProtocol.hysteria2 => 'hysteria2',
        NodeProtocol.tuic => 'tuic',
      };

  /// UDP-native protocols (QUIC-based). These carry UDP end to end, so unlike
  /// the TCP-only worker exit they don't need QUIC blocked.
  bool get isUdpNative =>
      this == NodeProtocol.hysteria2 || this == NodeProtocol.tuic;

  String get label => switch (this) {
        NodeProtocol.vless => 'VLESS',
        NodeProtocol.trojan => 'Trojan',
        NodeProtocol.shadowsocks => 'Shadowsocks',
        NodeProtocol.vmess => 'VMess',
        NodeProtocol.hysteria2 => 'Hysteria2',
        NodeProtocol.tuic => 'TUIC',
      };
}

class ProxyNode {
  ProxyNode({
    required this.protocol,
    required this.server,
    required this.port,
    this.tag = 'proxy',
    this.uuid,
    this.password,
    this.method,
    this.tls = false,
    this.sni,
    this.allowInsecure = false,
    this.alpn = const <String>[],
    this.fingerprint,
    this.flow,
    this.network = 'tcp',
    this.wsPath,
    this.wsHost,
    this.grpcServiceName,
    this.realityPublicKey,
    this.realityShortId,
    this.vmessAlterId = 0,
    this.vmessSecurity,
    this.obfsType,
    this.obfsPassword,
    this.congestionControl,
    this.udpRelayMode,
  });

  final NodeProtocol protocol;
  final String server;
  final int port;

  /// Display name (from the link fragment).
  final String tag;

  // Auth — protocol-specific.
  final String? uuid; // vless
  final String? password; // trojan / shadowsocks
  final String? method; // shadowsocks cipher

  // TLS.
  final bool tls;
  final String? sni;
  final bool allowInsecure;
  final List<String> alpn;
  final String? fingerprint; // uTLS fingerprint (e.g. "chrome")
  final String? flow; // vless flow (e.g. xtls-rprx-vision)

  // Transport.
  final String network; // tcp | ws | grpc | http
  final String? wsPath;
  final String? wsHost;
  final String? grpcServiceName;

  // VLESS-Reality (server_name is [sni]; these add the reality handshake).
  final String? realityPublicKey; // reality "pbk"
  final String? realityShortId; // reality "sid"

  // VMess.
  final int vmessAlterId; // "aid" (0 for AEAD)
  final String? vmessSecurity; // "scy": auto | aes-128-gcm | chacha20-poly1305 | none

  // Hysteria2 (QUIC). Auth uses [password]; salamander obfuscation is optional.
  final String? obfsType; // "salamander" when set
  final String? obfsPassword;

  // TUIC (QUIC). Auth uses [uuid] + [password].
  final String? congestionControl; // "bbr" | "cubic" | "new_reno"
  final String? udpRelayMode; // "native" | "quic"

  bool get isReality =>
      (realityPublicKey != null && realityPublicKey!.isNotEmpty);

  bool get hasTls => tls;

  /// Returns a copy with selected fields overridden. Used to stamp a Radar
  /// clean IP into a subscription template node: keep every protocol/transport
  /// field and only swap the address, port, and display name.
  ProxyNode copyWith({
    String? server,
    int? port,
    String? tag,
    String? sni,
    String? wsHost,
  }) {
    return ProxyNode(
      protocol: protocol,
      server: server ?? this.server,
      port: port ?? this.port,
      tag: tag ?? this.tag,
      uuid: uuid,
      password: password,
      method: method,
      tls: tls,
      sni: sni ?? this.sni,
      allowInsecure: allowInsecure,
      alpn: alpn,
      fingerprint: fingerprint,
      flow: flow,
      network: network,
      wsPath: wsPath,
      wsHost: wsHost ?? this.wsHost,
      grpcServiceName: grpcServiceName,
      realityPublicKey: realityPublicKey,
      realityShortId: realityShortId,
      vmessAlterId: vmessAlterId,
      vmessSecurity: vmessSecurity,
      obfsType: obfsType,
      obfsPassword: obfsPassword,
      congestionControl: congestionControl,
      udpRelayMode: udpRelayMode,
    );
  }
}
