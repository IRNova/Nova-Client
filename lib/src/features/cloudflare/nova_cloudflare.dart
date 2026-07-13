import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class CloudflareException implements Exception {
  CloudflareException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CfSession {
  const CfSession({required this.token, required this.accountId, required this.accountName, this.subdomain = ''});
  final String token;
  final String accountId;
  final String accountName;
  final String subdomain;
}

class CfWorker {
  const CfWorker(this.name, this.url);
  final String name;
  final String url;
}

class DeployResult {
  const DeployResult(this.workerName, this.workerUrl, this.installUrl);
  final String workerName;
  final String workerUrl;
  final String installUrl;
}

/// Persisted key/value for tokens, so the user stays signed in. Back it with
/// SharedPreferences in the app, or an in-memory map in tests.
abstract class CfStore {
  String get(String key);
  void set(String key, String value);
}

/// Dart port of the Android `NovaCloudflare`: OAuth (PKCE, loopback redirect on
/// the same public client wrangler uses) plus the Workers deploy API. Shared
/// across every platform; on desktop the loopback flow is a single shot (open
/// the browser, catch the redirect on 127.0.0.1).
class NovaCloudflare {
  NovaCloudflare(this._store, {http.Client? client}) : _client = client ?? http.Client();

  final CfStore _store;
  final http.Client _client;

  static const String _clientId = '54d11594-84e4-41aa-b438-e81b8fa78ee7';
  static const String _authUrl = 'https://dash.cloudflare.com/oauth2/auth';
  static const String _tokenUrl = 'https://dash.cloudflare.com/oauth2/token';
  static const String _apiBase = 'https://api.cloudflare.com/client/v4';
  static const int _redirectPort = 8976;
  static const String _redirectUri = 'http://localhost:8976/oauth/callback';
  static const String _workerSrc =
      'https://raw.githubusercontent.com/IRNova/Nova-Proxy/refs/heads/main/worker.js';
  static const List<String> _scopes = <String>[
    'account:read', 'user:read', 'workers:write', 'workers_kv:write',
    'workers_scripts:write', 'd1:write', 'pages:write', 'pages:read', 'zone:read',
    // NOTE: `account_analytics:read` was requested here (to show request usage vs
    // the free-plan limit) but Cloudflare's OAuth client rejects it outright
    // ("scope is invalid... not allowed to request scope account_analytics:read"),
    // which failed the ENTIRE sign-in. Removed. The usage read-out just shows
    // "unavailable"; the app already handles a null value.
  ];

  /// The Cloudflare free plan's Workers request allowance per day.
  static const int freeRequestsPerDay = 100000;

  final Random _rng = Random.secure();

  // Cloudflare's hosts (api.cloudflare.com, dash.cloudflare.com) and
  // raw.githubusercontent.com are filtered inside Iran, which is exactly where a
  // user setting up their first proxy has no working connection yet. When a
  // direct call fails at the network level we retry through the same same-origin
  // proxy the web installer uses (novaproxy.online/cf), then stick with it for
  // the rest of the session so we don't pay the direct timeout on every call.
  static const String _proxyBase = 'https://novaproxy.online/cf?url=';
  static const Duration _directTimeout = Duration(seconds: 12);
  static const Duration _proxyTimeout = Duration(seconds: 25);
  bool _preferProxy = false;

  String _via(String target) => '$_proxyBase${Uri.encodeComponent(target)}';

  /// Send a request to [target], falling back to the loopback-safe proxy if the
  /// direct call cannot reach Cloudflare (connection reset, DNS failure, or
  /// timeout, the usual shapes of Iran's filtering). A non-2xx *response* is a
  /// reachable server and is returned as-is; only thrown network errors trigger
  /// the retry.
  Future<http.Response> _http(String method, String target,
      {Map<String, String>? headers, Object? body}) async {
    Future<http.Response> run(String url) {
      final Uri u = Uri.parse(url);
      switch (method) {
        case 'GET':
          return _client.get(u, headers: headers);
        case 'PUT':
          return _client.put(u, headers: headers, body: body);
        case 'DELETE':
          return _client.delete(u, headers: headers, body: body);
        default:
          return _client.post(u, headers: headers, body: body);
      }
    }

    if (_preferProxy) return run(_via(target)).timeout(_proxyTimeout);
    try {
      return await run(target).timeout(_directTimeout);
    } catch (_) {
      final http.Response r = await run(_via(target)).timeout(_proxyTimeout);
      _preferProxy = true;
      return r;
    }
  }

  /// Multipart variant of [_http] for the worker upload. [build] must construct
  /// a fresh request each call, since a MultipartRequest can only be sent once.
  Future<http.StreamedResponse> _sendMultipart(
      String target, http.MultipartRequest Function(Uri uri) build) async {
    if (_preferProxy) {
      return _client.send(build(Uri.parse(_via(target)))).timeout(_proxyTimeout);
    }
    try {
      return await _client.send(build(Uri.parse(target))).timeout(_directTimeout);
    } catch (_) {
      final http.StreamedResponse r =
          await _client.send(build(Uri.parse(_via(target)))).timeout(_proxyTimeout);
      _preferProxy = true;
      return r;
    }
  }

  // The loopback listeners for the in-flight OAuth redirect, kept so a cancel
  // (user dismissed the sign-in sheet) can close them and unwind connect().
  HttpServer? _authServer4;
  HttpServer? _authServer6;

  // --- OAuth ---------------------------------------------------------------

  /// Aborts an in-flight [connect]. Closing the loopback listeners makes the
  /// pending `server.first` complete, so connect() returns instead of hanging
  /// on a redirect that will never arrive.
  void cancelConnect() {
    _authServer4?.close(force: true);
    _authServer6?.close(force: true);
    _authServer4 = null;
    _authServer6 = null;
  }

  /// Build the authorization URL for [verifier] (returns the URL + state so the
  /// caller can open it and validate the redirect).
  ({String url, String state}) authorizeUrl(String verifier) {
    final String challenge = _b64url(sha256.convert(utf8.encode(verifier)).bytes);
    final String state = _b64url(_randomBytes(32));
    final String url = '$_authUrl?${_query(<String, String>{
      'client_id': _clientId,
      'response_type': 'code',
      'redirect_uri': _redirectUri,
      'scope': _scopes.join(' '),
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    })}';
    return (url: url, state: state);
  }

  /// Full desktop sign-in: open the browser, catch the redirect on the loopback,
  /// exchange the code, resolve the account, and persist the session.
  Future<CfSession> connect({
    required FutureOr<void> Function(String url) openUrl,
    FutureOr<void> Function()? onRedirect,
  }) async {
    final String verifier = _b64url(_randomBytes(33));
    final ({String url, String state}) auth = authorizeUrl(verifier);
    // Listen on BOTH loopback stacks. The redirect URI is
    // http://localhost:8976/... and iOS resolves "localhost" to IPv6 (::1)
    // first; binding only 127.0.0.1 left the in-app browser stuck "loading
    // localhost" because nothing answered on ::1. Two sockets on the same port
    // (different addresses) is allowed; we take whichever receives the redirect.
    final HttpServer server4 =
        await HttpServer.bind(InternetAddress.loopbackIPv4, _redirectPort);
    HttpServer? server6;
    try {
      server6 =
          await HttpServer.bind(InternetAddress.loopbackIPv6, _redirectPort);
    } catch (_) {
      // IPv6 loopback unavailable on this device; IPv4 alone is fine.
    }
    _authServer4 = server4;
    _authServer6 = server6;
    try {
      await openUrl(auth.url);
      // `.first` on a server closed before any request arrives (a cancel)
      // throws StateError, so surface that as a clean "cancelled" instead of a
      // raw error. `firstOrNull`-style guard via onError.
      final HttpRequest? req = await Future.any<HttpRequest?>(<Future<HttpRequest?>>[
        server4.first,
        if (server6 != null) server6.first,
      ]).timeout(const Duration(minutes: 5)).catchError((_) => null);
      if (req == null) {
        throw CloudflareException('Sign-in was cancelled');
      }
      final Map<String, String> params = req.uri.queryParameters;
      final bool ok = params['error'] == null && params['code'] != null;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(_callbackHtml(ok, params['error'] ?? 'Invalid response'));
      await req.response.close();

      // Dismiss the in-app sign-in browser now, the instant the redirect lands,
      // so the user is not left staring at the callback page during the token
      // exchange and account lookup below (which can take a few seconds).
      if (onRedirect != null) await onRedirect();

      if (params['error'] != null) throw CloudflareException('Authorization failed: ${params['error']}');
      if (params['code'] == null || params['state'] != auth.state) {
        throw CloudflareException('Authorization was cancelled');
      }
      final _TokenSet tokens = await _exchangeToken(params['code']!, verifier);
      final ({String id, String name}) acct = await _fetchAccount(tokens.access);
      final String sub = await _accountSubdomain(tokens.access, acct.id);
      _persist(tokens, acct.id, acct.name, sub);
      return CfSession(token: tokens.access, accountId: acct.id, accountName: acct.name, subdomain: sub);
    } finally {
      await server4.close(force: true);
      await server6?.close(force: true);
      _authServer4 = null;
      _authServer6 = null;
    }
  }

  bool isConnected() => _store.get('cf_token').isNotEmpty;

  void disconnect() {
    for (final String k in <String>['cf_token', 'cf_refresh', 'cf_expires', 'cf_account_id', 'cf_account_name', 'cf_subdomain']) {
      _store.set(k, '');
    }
  }

  /// Rebuild a session from the saved token, refreshing first if needed.
  Future<CfSession?> restoreSession() async {
    if (_store.get('cf_token').isEmpty) return null;
    final String active = await _refreshIfNeeded() ?? _store.get('cf_token');
    if (active.isEmpty) return null;
    return CfSession(
      token: active,
      accountId: _store.get('cf_account_id'),
      accountName: _store.get('cf_account_name'),
      subdomain: _store.get('cf_subdomain'),
    );
  }

  Future<String?> _refreshIfNeeded() async {
    final String refresh = _store.get('cf_refresh');
    if (refresh.isEmpty) return null;
    final int expiresAt = int.tryParse(_store.get('cf_expires')) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < expiresAt - 120000) return null;
    final http.Response r = await _http('POST', _tokenUrl,
      headers: <String, String>{'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'},
      body: _query(<String, String>{'grant_type': 'refresh_token', 'refresh_token': refresh, 'client_id': _clientId}),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) return null;
    final Map<String, dynamic> j = jsonDecode(r.body) as Map<String, dynamic>;
    final String access = j['access_token'] as String? ?? '';
    if (access.isEmpty) return null;
    _store.set('cf_token', access);
    _store.set('cf_refresh', j['refresh_token'] as String? ?? refresh);
    _store.set('cf_expires', '${DateTime.now().millisecondsSinceEpoch + ((j['expires_in'] as num?)?.toInt() ?? 0) * 1000}');
    return access;
  }

  // --- Workers -------------------------------------------------------------

  Future<List<CfWorker>> listWorkers(CfSession s) async {
    final Map<String, dynamic> res = await _apiGet(s.token, '/accounts/${s.accountId}/workers/scripts');
    final List<dynamic> arr = (res['result'] as List<dynamic>?) ?? <dynamic>[];
    String sub = s.subdomain.isNotEmpty ? s.subdomain : _store.get('cf_subdomain');
    if (sub.isEmpty) {
      sub = await _accountSubdomain(s.token, s.accountId);
      if (sub.isNotEmpty) _store.set('cf_subdomain', sub);
    }
    final List<CfWorker> out = <CfWorker>[];
    for (final dynamic item in arr) {
      final String name = (item as Map<String, dynamic>)['id'] as String? ?? '';
      if (name.isEmpty) continue;
      out.add(CfWorker(name, sub.isNotEmpty ? 'https://$name.$sub.workers.dev' : ''));
    }
    out.sort((CfWorker a, CfWorker b) => a.name.compareTo(b.name));
    return out;
  }

  Future<({int kv, int d1})> resourceCounts(CfSession s) async {
    int kv = 0;
    int d1 = 0;
    try {
      kv = ((await _apiGet(s.token, '/accounts/${s.accountId}/storage/kv/namespaces?per_page=100'))['result'] as List<dynamic>?)?.length ?? 0;
    } catch (_) {}
    try {
      d1 = ((await _apiGet(s.token, '/accounts/${s.accountId}/d1/database?per_page=100'))['result'] as List<dynamic>?)?.length ?? 0;
    } catch (_) {}
    return (kv: kv, d1: d1);
  }

  /// Total Worker requests used so far today (UTC) across all scripts on the
  /// account, via Cloudflare's GraphQL analytics API. Returns null when the
  /// number can't be read (token lacks analytics scope, API unreachable, or the
  /// account has no data yet) so the UI can fall back gracefully rather than
  /// showing a wrong zero. Compare against [freeRequestsPerDay] for a usage bar.
  Future<int?> workerRequestsToday(CfSession s) async {
    final DateTime now = DateTime.now().toUtc();
    final DateTime start = DateTime.utc(now.year, now.month, now.day);
    const String query = 'query(\$tag: String!, \$start: Time!, \$end: Time!) {'
        ' viewer { accounts(filter: { accountTag: \$tag }) {'
        ' workersInvocationsAdaptive(limit: 10000,'
        ' filter: { datetime_geq: \$start, datetime_leq: \$end }) {'
        ' sum { requests } } } } }';
    try {
      final http.Response r = await _http('POST', '$_apiBase/graphql',
        headers: <String, String>{
          'Authorization': 'Bearer ${s.token}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'query': query,
          'variables': <String, dynamic>{
            'tag': s.accountId,
            'start': start.toIso8601String(),
            'end': now.toIso8601String(),
          },
        }),
      );
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      final Map<String, dynamic> j =
          (jsonDecode(r.body.isEmpty ? '{}' : r.body) as Map).cast<String, dynamic>();
      final Map<String, dynamic>? data = j['data'] as Map<String, dynamic>?;
      if (data == null) return null; // GraphQL errors → no usable data.
      final List<dynamic>? accounts =
          (data['viewer'] as Map<String, dynamic>?)?['accounts'] as List<dynamic>?;
      if (accounts == null || accounts.isEmpty) return null;
      final List<dynamic>? rows = (accounts.first
          as Map<String, dynamic>)['workersInvocationsAdaptive'] as List<dynamic>?;
      if (rows == null) return null;
      int total = 0;
      for (final dynamic row in rows) {
        final Map<String, dynamic>? sum =
            (row as Map<String, dynamic>)['sum'] as Map<String, dynamic>?;
        total += ((sum?['requests'] as num?)?.toInt() ?? 0);
      }
      return total;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteWorker(CfSession s, String name) async {
    final http.Response r = await _http('DELETE', '$_apiBase/accounts/${s.accountId}/workers/scripts/$name',
      headers: <String, String>{'Authorization': 'Bearer ${s.token}'},
    );
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw CloudflareException('Could not delete the worker (${r.statusCode})');
    }
  }

  Future<DeployResult> updateWorker(CfSession s, String name, {void Function(String)? onProgress}) =>
      deploy(s, name, overwrite: true, onProgress: onProgress);

  Future<DeployResult> deploy(
    CfSession s,
    String workerName, {
    bool overwrite = false,
    void Function(String)? onProgress,
  }) async {
    void progress(String m) => onProgress?.call(m);
    final String aid = s.accountId;
    final String token = s.token;

    if (!overwrite) {
      progress('Checking the name');
      if (await _workerExists(token, aid, workerName)) {
        throw CloudflareException('A worker named "$workerName" already exists. Choose a different name.');
      }
    }

    progress('Preparing code, storage and database');
    final List<dynamic> results = await Future.wait(<Future<dynamic>>[
      _fetchWorkerCode(),
      _getOrCreateKv(token, aid, '$workerName-vault'),
      _getOrCreateD1(token, aid, '$workerName-db'),
      _accountSubdomain(token, aid),
    ]);
    final List<int> code = results[0] as List<int>;
    final String kvId = results[1] as String;
    final String d1Id = results[2] as String;
    final String subdomain = results[3] as String;

    progress('Uploading the worker');
    await _uploadWorker(token, aid, workerName, code, kvId, d1Id);

    progress('Publishing');
    await _enableSubdomain(token, aid, workerName);

    final String url = subdomain.isNotEmpty ? 'https://$workerName.$subdomain.workers.dev' : '';
    return DeployResult(workerName, url, url.isNotEmpty ? '$url/install' : '');
  }

  Future<bool> _workerExists(String token, String aid, String name) async {
    try {
      final http.Response r = await _http('GET', '$_apiBase/accounts/$aid/workers/scripts/$name',
        headers: <String, String>{'Authorization': 'Bearer $token'},
      );
      return r.statusCode >= 200 && r.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<int>> _fetchWorkerCode() async {
    final http.Response r = await _http('GET', _workerSrc);
    if (r.statusCode < 200 || r.statusCode >= 300 || r.bodyBytes.isEmpty) {
      throw CloudflareException('Could not fetch the worker');
    }
    return r.bodyBytes;
  }

  Future<String> _getOrCreateKv(String token, String aid, String title) async {
    final Map<String, dynamic> list = await _apiGet(token, '/accounts/$aid/storage/kv/namespaces?per_page=100');
    for (final dynamic ns in (list['result'] as List<dynamic>?) ?? <dynamic>[]) {
      if ((ns as Map<String, dynamic>)['title'] == title) return ns['id'] as String;
    }
    final Map<String, dynamic> created = await _apiPost(token, '/accounts/$aid/storage/kv/namespaces', <String, dynamic>{'title': title});
    return (created['result'] as Map<String, dynamic>)['id'] as String;
  }

  Future<String> _getOrCreateD1(String token, String aid, String name) async {
    final Map<String, dynamic> list = await _apiGet(token, '/accounts/$aid/d1/database?name=$name');
    for (final dynamic db in (list['result'] as List<dynamic>?) ?? <dynamic>[]) {
      final Map<String, dynamic> m = db as Map<String, dynamic>;
      if (m['name'] == name) return (m['uuid'] ?? m['id']) as String;
    }
    final Map<String, dynamic> created = await _apiPost(token, '/accounts/$aid/d1/database', <String, dynamic>{'name': name});
    final Map<String, dynamic> r = created['result'] as Map<String, dynamic>;
    return (r['uuid'] ?? r['id']) as String;
  }

  Future<String> _accountSubdomain(String token, String aid) async {
    try {
      final Map<String, dynamic> res = await _apiGet(token, '/accounts/$aid/workers/subdomain');
      return (res['result'] as Map<String, dynamic>?)?['subdomain'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _uploadWorker(String token, String aid, String name, List<int> code, String kvId, String d1Id) async {
    final String metadata = jsonEncode(<String, dynamic>{
      'main_module': 'worker.js',
      'compatibility_date': '2025-01-01',
      'compatibility_flags': <String>['nodejs_compat', 'global_fetch_strictly_public'],
      'bindings': <Map<String, dynamic>>[
        <String, dynamic>{'type': 'kv_namespace', 'name': 'KV', 'namespace_id': kvId},
        <String, dynamic>{'type': 'd1', 'name': 'DB', 'database_id': d1Id},
      ],
    });
    final http.StreamedResponse resp = await _sendMultipart(
      '$_apiBase/accounts/$aid/workers/scripts/$name',
      (Uri uri) => http.MultipartRequest('PUT', uri)
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromString('metadata', metadata, contentType: MediaType('application', 'json')))
        ..files.add(http.MultipartFile.fromBytes('worker.js', code,
            filename: 'worker.js', contentType: MediaType('application', 'javascript+module'))),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw CloudflareException('Worker upload failed (${resp.statusCode}): ${await resp.stream.bytesToString()}');
    }
  }

  Future<void> _enableSubdomain(String token, String aid, String name) =>
      _apiPost(token, '/accounts/$aid/workers/scripts/$name/subdomain', <String, dynamic>{'enabled': true});

  // --- token + api helpers -------------------------------------------------

  Future<_TokenSet> _exchangeToken(String code, String verifier) async {
    final http.Response r = await _http('POST', _tokenUrl,
      headers: <String, String>{'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json'},
      body: _query(<String, String>{
        'client_id': _clientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': _redirectUri,
        'grant_type': 'authorization_code',
      }),
    );
    final Map<String, dynamic> j = (jsonDecode(r.body.isEmpty ? '{}' : r.body) as Map).cast<String, dynamic>();
    final String token = j['access_token'] as String? ?? '';
    if (r.statusCode < 200 || r.statusCode >= 300 || token.isEmpty) {
      throw CloudflareException('Token exchange failed: ${j['error_description'] ?? j['error'] ?? 'no token'}');
    }
    return _TokenSet(
      token,
      j['refresh_token'] as String? ?? '',
      DateTime.now().millisecondsSinceEpoch + ((j['expires_in'] as num?)?.toInt() ?? 0) * 1000,
    );
  }

  Future<({String id, String name})> _fetchAccount(String token) async {
    final Map<String, dynamic> res = await _apiGet(token, '/accounts?per_page=1');
    final List<dynamic> list = (res['result'] as List<dynamic>?) ?? <dynamic>[];
    if (list.isEmpty) throw CloudflareException('No Cloudflare account found');
    final Map<String, dynamic> first = list.first as Map<String, dynamic>;
    return (id: first['id'] as String? ?? '', name: first['name'] as String? ?? '');
  }

  void _persist(_TokenSet t, String id, String name, String sub) {
    _store.set('cf_token', t.access);
    _store.set('cf_refresh', t.refresh);
    _store.set('cf_expires', '${t.expiresAt}');
    _store.set('cf_account_id', id);
    _store.set('cf_account_name', name);
    if (sub.isNotEmpty) _store.set('cf_subdomain', sub);
  }

  Future<Map<String, dynamic>> _apiGet(String token, String path) async {
    final http.Response r = await _http('GET', '$_apiBase$path', headers: <String, String>{'Authorization': 'Bearer $token'});
    if (r.statusCode < 200 || r.statusCode >= 300) throw CloudflareException('Cloudflare API error (${r.statusCode})');
    return (jsonDecode(r.body.isEmpty ? '{}' : r.body) as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _apiPost(String token, String path, Map<String, dynamic> body) async {
    final http.Response r = await _http('POST', '$_apiBase$path',
      headers: <String, String>{'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (r.statusCode < 200 || r.statusCode >= 300) throw CloudflareException('Cloudflare API error (${r.statusCode}): ${r.body}');
    return (jsonDecode(r.body.isEmpty ? '{}' : r.body) as Map).cast<String, dynamic>();
  }

  String _query(Map<String, String> m) =>
      m.entries.map((MapEntry<String, String> e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');

  String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  List<int> _randomBytes(int n) => List<int>.generate(n, (_) => _rng.nextInt(256));

  String _callbackHtml(bool ok, String error) {
    final String enTitle = ok ? 'Nova is connected' : 'Sign-in failed';
    final String faTitle = ok ? 'نوا متصل شد' : 'ورود ناموفق بود';
    final String enMsg = ok ? 'You can return to Nova now.' : error;
    final String faMsg = ok ? 'حالا می‌توانید به نوا برگردید.' : error;
    final String color = ok ? '#22D3EE' : '#F87171';
    // Deep link back into the app (scheme registered in the Android manifest and
    // the iOS/macOS Info.plist). On mobile the app also dismisses this page
    // automatically; the button is the fallback, and the main path on desktop
    // where the sign-in opens in an external browser that can't self-close.
    final String button = ok
        ? '<a class="b" href="novaclient://oauth-return">بازگشت به نوا&nbsp;&nbsp;·&nbsp;&nbsp;Return to Nova</a>'
        : '';
    return '<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>body{background:#05060A;color:#EAECF2;'
        'font-family:-apple-system,system-ui,"Segoe UI",Roboto,sans-serif;'
        'display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}'
        '.c{text-align:center;padding:32px;max-width:360px}'
        'h1{color:$color;font-size:22px;margin:0 0 6px}'
        'h2{color:$color;font-size:18px;margin:22px 0 6px;font-weight:600}'
        'p{color:#B6BCC9;margin:4px 0;font-size:15px}'
        '.b{display:inline-block;margin-top:26px;padding:14px 28px;border-radius:12px;'
        'background:linear-gradient(120deg,#22D3EE,#818CF8,#A855F7);color:#05060A;'
        'font-weight:700;text-decoration:none;font-size:15px}</style></head>'
        '<body><div class="c">'
        '<h1>$faTitle</h1><p>$faMsg</p>'
        '<h2 dir="ltr">$enTitle</h2><p dir="ltr">$enMsg</p>'
        '$button'
        '</div></body></html>';
  }
}

class _TokenSet {
  const _TokenSet(this.access, this.refresh, this.expiresAt);
  final String access;
  final String refresh;
  final int expiresAt;
}
