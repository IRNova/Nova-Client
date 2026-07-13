import 'dart:convert';

import 'package:http/http.dart' as http;

/// A signed-in session against a Nova panel (the worker's `/admin` API). The
/// cookie is pinned to the User-Agent, so every request reuses [NovaPanel.ua].
class PanelSession {
  const PanelSession(this.workerUrl, this.authCookie);
  final String workerUrl;
  final String authCookie;
}

class PanelException implements Exception {
  PanelException(this.message, {this.need2fa = false});
  final String message;
  final bool need2fa;
  @override
  String toString() => message;
}

class Whoami {
  Whoami({this.asn = 0, this.isp = '', this.country = '', this.city = '', this.carrier = ''});
  final int asn;
  final String isp;
  final String country;
  final String city;
  final String carrier;
}

class SecurityStatus {
  SecurityStatus({this.twofa = false, this.passwordSource = '', this.kvSet = false});
  final bool twofa;
  final String passwordSource;
  final bool kvSet;
}

/// Dart port of the Android `NovaPanel`. Talks to a Nova worker's panel API over
/// HTTP, the same endpoints across every platform.
///
/// A custom panel domain can sit behind Cloudflare bot protection, which closes
/// requests with no recognizable User-Agent; always send [ua] (and the worker
/// pins the session cookie to it).
class NovaPanel {
  NovaPanel({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const String ua = 'Nova/1.0.0 (desktop; sing-box)';

  Map<String, String> get _baseHeaders => <String, String>{'User-Agent': ua};

  Future<PanelSession> login(String workerUrl, String password, {String? code}) async {
    final String base = _normalizeBase(workerUrl);
    final String form = <String>[
      'password=${Uri.encodeQueryComponent(password)}',
      if (code != null && code.isNotEmpty) 'code=${Uri.encodeQueryComponent(code)}',
    ].join('&');

    final http.Response r = await _client.post(
      Uri.parse('$base/login'),
      headers: <String, String>{..._baseHeaders, 'Content-Type': 'application/x-www-form-urlencoded'},
      body: form,
    );
    final Map<String, dynamic> data = _tryJson(r.body);
    if (data['need2fa'] == true) {
      throw PanelException('two-factor code required', need2fa: true);
    }
    final String serverError =
        (data['error'] as String?)?.trim().isNotEmpty == true ? data['error'] as String : (data['message'] as String? ?? '');
    if (serverError == 'rate_limited') {
      throw PanelException('Too many attempts. Try again later.');
    }
    final String? cookie = _extractAuthCookie(r.headers['set-cookie']);
    final bool ok = data['success'] == true || (r.statusCode >= 200 && r.statusCode < 300 && cookie != null);
    if (!ok) {
      final String msg = serverError.isNotEmpty
          ? serverError
          : (r.statusCode == 401 || r.statusCode == 403)
              ? 'Wrong password'
              : r.statusCode >= 500
                  ? 'Panel server error (${r.statusCode}). Please try again.'
                  : r.statusCode >= 400
                      ? 'Login failed (${r.statusCode})'
                      : 'Wrong password';
      throw PanelException(msg);
    }
    if (cookie == null) throw PanelException('Login succeeded but no session was returned');
    return PanelSession(base, cookie);
  }

  Future<Whoami> whoami(PanelSession s) async {
    final Map<String, dynamic> d = await _getJson(s, '/admin/whoami');
    return Whoami(
      asn: (d['asn'] as num?)?.toInt() ?? 0,
      isp: d['isp'] as String? ?? '',
      country: d['country'] as String? ?? '',
      city: d['city'] as String? ?? '',
      carrier: d['carrier'] as String? ?? '',
    );
  }

  Future<SecurityStatus> securityStatus(PanelSession s) async {
    final Map<String, dynamic> d = await _getJson(s, '/admin/security/status');
    return SecurityStatus(
      twofa: d['twofa'] == true,
      passwordSource: d['passwordSource'] as String? ?? '',
      kvSet: d['kvSet'] == true,
    );
  }

  Future<Map<String, dynamic>> getConfig(PanelSession s) => _getJson(s, '/admin/config.json');

  Future<String> subContent(PanelSession s) => _getText(s, '/admin/sub-content');

  /// Prefer the worker's real subscription URL (auto-updates + reports
  /// usage/expiry) from the config token; fall back to a one-time snapshot.
  Future<String> importableSubscription(PanelSession s) async {
    final Map<String, dynamic> cfg = await getConfig(s);
    final String token =
        (cfg['optimizedSubGeneration'] as Map?)?.cast<String, dynamic>()['TOKEN'] as String? ?? '';
    if (token.isNotEmpty) {
      return '${s.workerUrl}/sub?token=$token';
    }
    return subContent(s);
  }

  Future<bool> installConfigured(String workerUrl) async {
    final String base = _normalizeBase(workerUrl);
    try {
      final http.Response r = await _client.get(Uri.parse('$base/install/status'), headers: _baseHeaders);
      final Map<String, dynamic> d = _tryJson(r.body);
      return d['admin'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> installSet(String workerUrl, String password) async {
    final String base = _normalizeBase(workerUrl);
    final http.Response r = await _client.post(
      Uri.parse('$base/install/set'),
      headers: <String, String>{..._baseHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode(<String, String>{'password': password}),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PanelException('Could not set the panel password (${r.statusCode})');
    }
  }

  // --- panel admin: config / network settings / custom IPs ----------------

  /// Save the panel config (HOST/UUID are read-only server-side; the editable
  /// bits are tlsFragment / skipCertVerify / enable0RTT / randomPath).
  Future<Map<String, dynamic>> saveConfig(
          PanelSession s, Map<String, dynamic> config) =>
      _postJson(s, '/admin/config.json', config);

  /// The worker's routing/DNS/WARP/limits document (the bulk of the panel's
  /// "settings"). Read + save the whole JSON so unknown keys are preserved.
  Future<Map<String, dynamic>> getNetworkSettings(PanelSession s) =>
      _getJson(s, '/admin/network-settings.json');

  Future<Map<String, dynamic>> saveNetworkSettings(
          PanelSession s, Map<String, dynamic> settings) =>
      _postJson(s, '/admin/network-settings.json', settings);

  /// The worker's custom clean-IP list (ADD.txt), raw newline-separated text.
  Future<String> getIPs(PanelSession s) => _getText(s, '/admin/ADD.txt');

  Future<Map<String, dynamic>> saveIPs(PanelSession s, String text) =>
      _postText(s, '/admin/ADD.txt', text);

  /// Usage data (per-day/route buckets) for the panel's usage graphs.
  Future<Map<String, dynamic>> usageData(PanelSession s) =>
      _getJson(s, '/admin/usage-data');

  // --- helpers -------------------------------------------------------------

  Future<Map<String, dynamic>> _postJson(
      PanelSession s, String path, Map<String, dynamic> body) async {
    final http.Response r = await _client.post(
      Uri.parse('${s.workerUrl}$path'),
      headers: <String, String>{
        ..._baseHeaders,
        'Cookie': s.authCookie,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return _handleWrite(r);
  }

  Future<Map<String, dynamic>> _postText(
      PanelSession s, String path, String body) async {
    final http.Response r = await _client.post(
      Uri.parse('${s.workerUrl}$path'),
      headers: <String, String>{
        ..._baseHeaders,
        'Cookie': s.authCookie,
        'Content-Type': 'text/plain',
      },
      body: body,
    );
    return _handleWrite(r);
  }

  Map<String, dynamic> _handleWrite(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw PanelException('Session expired, please sign in again');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      final String err = _tryJson(r.body)['error'] as String? ?? '';
      throw PanelException(err.isNotEmpty ? err : 'Save failed (${r.statusCode})');
    }
    return _tryJson(r.body);
  }

  Future<Map<String, dynamic>> _getJson(PanelSession s, String path) async {
    final String body = await _getText(s, path);
    return _tryJson(body);
  }

  Future<String> _getText(PanelSession s, String path) async {
    final http.Response r = await _client.get(
      Uri.parse('${s.workerUrl}$path'),
      headers: <String, String>{..._baseHeaders, 'Cookie': s.authCookie},
    );
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw PanelException('Session expired, please sign in again');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PanelException('Panel error (${r.statusCode})');
    }
    return r.body;
  }

  Map<String, dynamic> _tryJson(String body) {
    try {
      final dynamic v = jsonDecode(body.isEmpty ? '{}' : body);
      return v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String? _extractAuthCookie(String? setCookie) {
    if (setCookie == null) return null;
    // http joins multiple Set-Cookie with ", "; find the auth=... pair.
    for (final String part in setCookie.split(RegExp(r',(?=[^ ])|, '))) {
      final String first = part.split(';').first.trim();
      if (first.startsWith('auth=')) return first;
    }
    for (final String part in setCookie.split(';')) {
      final String t = part.trim();
      if (t.startsWith('auth=')) return t;
    }
    return null;
  }

  String _normalizeBase(String url) {
    String u = url.trim();
    if (!u.startsWith('http')) u = 'https://$u';
    u = u.replaceAll(RegExp(r'/+$'), '');
    if (u.endsWith('/admin')) u = u.substring(0, u.length - '/admin'.length);
    if (u.endsWith('/login')) u = u.substring(0, u.length - '/login'.length);
    return u.replaceAll(RegExp(r'/+$'), '');
  }
}
