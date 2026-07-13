import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nova_client/src/features/cloudflare/nova_cloudflare.dart';

class _MemStore implements CfStore {
  final Map<String, String> _m = {};
  @override
  String get(String k) => _m[k] ?? '';
  @override
  void set(String k, String v) => _m[k] = v;
}

void main() {
  test('PKCE authorize URL is well-formed', () {
    final cf = NovaCloudflare(_MemStore());
    const verifier = 'test-verifier-abc123';
    final a = cf.authorizeUrl(verifier);
    final expectedChallenge =
        base64Url.encode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
    expect(a.url, contains('client_id=54d11594-84e4-41aa-b438-e81b8fa78ee7'));
    expect(a.url, contains('code_challenge_method=S256'));
    expect(a.url, contains('code_challenge=$expectedChallenge'));
    expect(a.url, contains('redirect_uri='));
    expect(a.state.isNotEmpty, isTrue);
  });

  test('worker source is fetchable (deploy step 1)', () async {
    final r = await http.get(Uri.parse(
        'https://raw.githubusercontent.com/IRNova/Nova-Proxy/refs/heads/main/worker.js'));
    expect(r.statusCode, 200);
    expect(r.bodyBytes.length, greaterThan(1000));
  });
}
