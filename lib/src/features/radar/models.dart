// Data models for Nova Radar — the Cloudflare clean-IP scanner consolidated
// into Nova Client. Ported from the original NovaRadar Go backend
// (IRNova/NovaRadar: sources.go / scanner.go).

enum SourceType { cidr, proxyip, domain }

extension SourceTypeName on SourceType {
  String get wire => switch (this) {
        SourceType.cidr => 'cidr',
        SourceType.proxyip => 'proxyip',
        SourceType.domain => 'domain',
      };

  static SourceType parse(String s) => switch (s) {
        'proxyip' => SourceType.proxyip,
        'domain' => SourceType.domain,
        _ => SourceType.cidr,
      };
}

/// A selectable source of candidate IPs (a CIDR list, a reverse-proxy IP list,
/// or a list of domains to resolve).
class IpSource {
  IpSource({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    required this.enabled,
  });

  final String id;
  final String name;
  final String url;
  final SourceType type;
  bool enabled;

  IpSource copyWith({bool? enabled}) => IpSource(
        id: id,
        name: name,
        url: url,
        type: type,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'url': url,
        'type': type.wire,
        'enabled': enabled,
      };

  factory IpSource.fromJson(Map<String, dynamic> json) => IpSource(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        type: SourceTypeName.parse(json['type'] as String? ?? 'cidr'),
        enabled: json['enabled'] as bool? ?? false,
      );
}

/// A working IP found by the scanner.
class ScanResult {
  ScanResult({
    required this.ip,
    required this.port,
    required this.link,
    required this.latencyMs,
    this.jitterMs = 0,
    this.lossPct = 0,
    double? score,
  }) : score = score ?? (latencyMs + jitterMs * 0.5 + lossPct * 20);

  final String ip;
  final int port;
  final String link;

  /// Average latency across the probes that answered, in milliseconds.
  final int latencyMs;

  /// Spread between the fastest and slowest answering probe (max - min), in ms.
  /// High jitter means an unstable exit even if its average looks quick.
  final int jitterMs;

  /// Percentage of probes that got no answer (0-100). A low-latency IP that
  /// drops packets is worse than a slightly slower one that never does.
  final int lossPct;

  /// Composite quality score, lower is better: `latency + jitter*0.5 + loss*20`.
  /// This matches the Nova panel's Radar so both rank clean IPs the same way,
  /// favouring stable exits over ones that merely handshake fast.
  final double score;

  String get hostPort => '$ip:$port';
}

/// Live scan statistics streamed to the UI (mirrors NovaRadar's ScanStats).
class ScanStats {
  const ScanStats({
    this.totalScanned = 0,
    this.totalToScan = 0,
    this.aliveCount = 0,
    this.deadCount = 0,
    this.scanning = false,
    this.currentIp = '',
    this.currentPort = 0,
    this.elapsedSec = 0,
    this.remainingSec = 0,
    this.secondPass = false,
  });

  final int totalScanned;
  final int totalToScan;
  final int aliveCount;
  final int deadCount;
  final bool scanning;
  final String currentIp;
  final int currentPort;
  final int elapsedSec;
  final int remainingSec;
  final bool secondPass;

  double get progress {
    if (totalToScan == 0) return 0;
    return (totalScanned / totalToScan).clamp(0.0, 1.0).toDouble();
  }

  static const ScanStats idle = ScanStats();

  ScanStats copyWith({
    int? totalScanned,
    int? totalToScan,
    int? aliveCount,
    int? deadCount,
    bool? scanning,
    String? currentIp,
    int? currentPort,
    int? elapsedSec,
    int? remainingSec,
    bool? secondPass,
  }) {
    return ScanStats(
      totalScanned: totalScanned ?? this.totalScanned,
      totalToScan: totalToScan ?? this.totalToScan,
      aliveCount: aliveCount ?? this.aliveCount,
      deadCount: deadCount ?? this.deadCount,
      scanning: scanning ?? this.scanning,
      currentIp: currentIp ?? this.currentIp,
      currentPort: currentPort ?? this.currentPort,
      elapsedSec: elapsedSec ?? this.elapsedSec,
      remainingSec: remainingSec ?? this.remainingSec,
      secondPass: secondPass ?? this.secondPass,
    );
  }
}

/// The TLS ports — these get a real TLS handshake in the deep test; others get
/// a TCP read probe. (From NovaRadar's `tlsPorts`.)
const Set<int> kTlsPorts = <int>{443, 2053, 2083, 2087, 2096, 8443};

/// All ports Nova Radar can probe (TLS group first, then HTTP group).
const List<int> kAllPorts = <int>[
  443, 2053, 2083, 2087, 2096, 8443, // TLS
  80, 2052, 2082, 2086, 2095, 8080, // HTTP
];

/// The SNI presented during the deep-test TLS handshake (Nova Worker host).
const String kVlessSni = 'nova2.altramax083.workers.dev';

/// SNI used for Radar's TLS reachability probes. Deliberately NOT the worker's
/// `*.workers.dev` host: Iran's DPI resets that SNI, so probing with it made
/// Radar find zero clean IPs from Iran. A benign Cloudflare SNI completes the
/// handshake on every CF edge IP (an IP literal or empty SNI does not, reliably)
/// while giving DPI nothing worth blocking. Real Nova traffic fragments its own
/// SNI, so a reachable edge IP is exactly what "clean" means for the client.
const String kRadarProbeSni = 'www.cloudflare.com';
