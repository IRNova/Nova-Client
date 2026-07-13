import 'package:flutter_test/flutter_test.dart';
import 'package:nova_client/src/features/cloudflare/nova_panel.dart';

void main() {
  test('panel install status reachable against real worker', () async {
    final panel = NovaPanel();
    final bool configured = await panel.installConfigured('https://sub.lillio.org');
    // The user's panel is set up, so this should be true (and proves the Dart
    // client's HTTP + User-Agent + JSON parsing work end to end).
    expect(configured, isTrue);
  });
}
