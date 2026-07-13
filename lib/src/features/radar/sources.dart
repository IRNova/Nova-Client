import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'models.dart';

/// The default IP sources, ported 1:1 from NovaRadar's `DefaultSources`.
List<IpSource> defaultSources() => <IpSource>[
      IpSource(id: 'official', name: 'Cloudflare Official', url: 'https://www.cloudflare.com/ips-v4/', type: SourceType.cidr, enabled: true),
      IpSource(id: 'cm', name: 'CM List', url: 'https://raw.githubusercontent.com/cmliu/cmliu/main/CF-CIDR.txt', type: SourceType.cidr, enabled: false),
      IpSource(id: 'as13335', name: 'AS13335 (Cloudflare)', url: 'https://raw.githubusercontent.com/ipverse/asn-ip/master/as/13335/ipv4-aggregated.txt', type: SourceType.cidr, enabled: false),
      IpSource(id: 'as209242', name: 'AS209242 (Cloudflare)', url: 'https://raw.githubusercontent.com/ipverse/asn-ip/master/as/209242/ipv4-aggregated.txt', type: SourceType.cidr, enabled: false),
      IpSource(id: 'as24429', name: 'AS24429 (Alibaba)', url: 'https://raw.githubusercontent.com/ipverse/asn-ip/master/as/24429/ipv4-aggregated.txt', type: SourceType.cidr, enabled: false),
      IpSource(id: 'as199524', name: 'AS199524 (G-Core)', url: 'https://raw.githubusercontent.com/ipverse/asn-ip/master/as/199524/ipv4-aggregated.txt', type: SourceType.cidr, enabled: false),
      IpSource(id: 'proxyip', name: 'Reverse Proxy IPs', url: 'https://raw.githubusercontent.com/cmliu/ACL4SSR/main/baipiao.txt', type: SourceType.proxyip, enabled: false),
      IpSource(id: 'dominos', name: 'Foreign Domains', url: 'https://raw.githubusercontent.com/Blacknuno/Nova-Proxy/refs/heads/main/dominos.text', type: SourceType.domain, enabled: false),
      IpSource(id: 'irdominos', name: 'Iranian Domains', url: 'https://raw.githubusercontent.com/Blacknuno/Nova-Proxy/refs/heads/main/IRdominos.text', type: SourceType.domain, enabled: false),
    ];

/// Cloudflare's published v4 ranges, used when no source returns CIDRs.
const List<String> _fallbackCidrs = <String>[
  '173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22',
  '141.101.64.0/18', '108.162.192.0/18', '190.93.240.0/20', '188.114.96.0/20',
  '197.234.240.0/22', '198.41.128.0/17', '162.158.0.0/15', '104.16.0.0/13',
  '104.24.0.0/14', '172.64.0.0/13', '131.0.72.0/22',
];

/// The collected candidate space from the enabled sources.
class CandidatePool {
  CandidatePool(this.cidrs, this.directIps);
  final List<String> cidrs;
  final List<String> directIps;
}

/// Fetches all enabled sources in parallel and returns CIDRs + direct IPs.
/// Falls back to the built-in Cloudflare ranges if no CIDRs are gathered.
Future<CandidatePool> fetchIpsFromSources(List<IpSource> sources) async {
  final List<String> cidrs = <String>[];
  final List<String> directIps = <String>[];

  await Future.wait(sources.where((s) => s.enabled).map((s) async {
    try {
      final String text = await _fetchUrl(s.url);
      switch (s.type) {
        case SourceType.cidr:
          cidrs.addAll(_parseCidrLines(text));
        case SourceType.proxyip:
          directIps.addAll(_parseProxyIpLines(text));
        case SourceType.domain:
          final domains = _parseDomainLines(text);
          directIps.addAll(await _resolveDomains(domains));
      }
    } catch (_) {
      // A failing source must not abort the whole scan.
    }
  }));

  if (cidrs.isEmpty) {
    cidrs.addAll(_fallbackCidrs);
  }
  return CandidatePool(cidrs, directIps);
}

/// Generates up to [count] random IPv4 addresses spread across [cidrs].
List<String> generateRandomIps(List<String> cidrs, int count) {
  if (cidrs.isEmpty) return <String>[];
  final Random rng = Random.secure();
  final Set<String> ips = <String>{};
  final int perCidr = (count ~/ cidrs.length) + 1;

  for (final String cidr in cidrs) {
    final _Range? range = _parseCidr(cidr);
    if (range == null) continue;
    final int total = range.end - range.start;
    if (total < 2) continue;

    for (int j = 0; j < perCidr && ips.length < count; j++) {
      final int offset = _randUint32(rng, total);
      ips.add(_uint32ToIp(range.start + 1 + (offset % total)));
    }
    if (ips.length >= count) break;
  }
  return ips.toList();
}

// ---------------------------------------------------------------------------
// Parsing helpers (ported from sources.go)
// ---------------------------------------------------------------------------

List<String> _parseCidrLines(String text) {
  final List<String> out = <String>[];
  for (String line in text.split('\n')) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (_parseCidr(line) != null) out.add(line);
  }
  return out;
}

List<String> _parseProxyIpLines(String text) {
  final Set<String> seen = <String>{};
  final List<String> out = <String>[];
  for (String line in text.split('\n')) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.contains('#')) line = line.split('#').first.trim();
    String ip = line.contains(':') ? line.split(':').first.trim() : line;
    if (_isIpv4(ip) && seen.add(ip)) out.add(ip);
  }
  return out;
}

List<String> _parseDomainLines(String text) {
  final List<String> out = <String>[];
  for (String line in text.split('\n')) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.contains('#')) line = line.split('#').first.trim();
    if (line.isNotEmpty) out.add(line);
  }
  return out;
}

Future<List<String>> _resolveDomains(List<String> domains) async {
  final List<String> ips = <String>[];
  final int limit = min(domains.length, 100);
  // Bound concurrency to ~10 lookups at a time (matches the Go semaphore).
  for (int i = 0; i < limit; i += 10) {
    final batch = domains.sublist(i, min(i + 10, limit));
    final results = await Future.wait(batch.map((d) async {
      try {
        final addrs = await InternetAddress.lookup(d);
        return addrs
            .where((a) => a.type == InternetAddressType.IPv4)
            .map((a) => a.address)
            .toList();
      } catch (_) {
        return const <String>[];
      }
    }));
    for (final r in results) {
      ips.addAll(r);
    }
  }
  return ips;
}

Future<String> _fetchUrl(String url) async {
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final HttpClientRequest req = await client.getUrl(Uri.parse(url));
    req.followRedirects = true;
    final HttpClientResponse resp = await req.close();
    final StringBuffer buffer = StringBuffer();
    await for (final chunk in resp.transform(const _Utf8Lossy())) {
      buffer.write(chunk);
    }
    return buffer.toString();
  } finally {
    client.close(force: true);
  }
}

// ---------------------------------------------------------------------------
// IPv4 / CIDR math
// ---------------------------------------------------------------------------

class _Range {
  _Range(this.start, this.end);
  final int start;
  final int end;
}

bool _isIpv4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return false;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
  }
  return true;
}

_Range? _parseCidr(String cidr) {
  final slash = cidr.indexOf('/');
  if (slash < 0) return null;
  final ipPart = cidr.substring(0, slash);
  final ones = int.tryParse(cidr.substring(slash + 1));
  if (ones == null || ones < 0 || ones > 32) return null;
  final int? base = _ipToUint32(ipPart);
  if (base == null) return null;
  // Mask the base to the network address.
  final int mask = ones == 0 ? 0 : (0xFFFFFFFF << (32 - ones)) & 0xFFFFFFFF;
  final int start = base & mask;
  final int count = 1 << (32 - ones);
  final int end = start + count - 1;
  return _Range(start, end);
}

int? _ipToUint32(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;
  int value = 0;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    value = (value << 8) | n;
  }
  return value & 0xFFFFFFFF;
}

String _uint32ToIp(int n) {
  return '${(n >> 24) & 0xFF}.${(n >> 16) & 0xFF}.${(n >> 8) & 0xFF}.${n & 0xFF}';
}

int _randUint32(Random rng, int bound) {
  if (bound <= 0) return 0;
  // Compose a 32-bit value from two 16-bit draws, then mod into range.
  final int hi = rng.nextInt(1 << 16);
  final int lo = rng.nextInt(1 << 16);
  return ((hi << 16) | lo) % bound;
}

/// A lossy UTF-8 decoder that won't throw on the occasional malformed byte in
/// a remote list (equivalent to Go's tolerant string read).
class _Utf8Lossy extends StreamTransformerBase<List<int>, String> {
  const _Utf8Lossy();
  @override
  Stream<String> bind(Stream<List<int>> stream) {
    return stream.map((bytes) => String.fromCharCodes(bytes));
  }
}
