import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_client/src/core/models/proxy_profile.dart';
import 'package:nova_client/src/core/proxy/proxy_controller.dart';

/// A controller that reproduces the iOS/macOS Network Extension timing that
/// [ProxyController.reconnect] exists to handle: `stop()` returns *before* the
/// tunnel has actually reached `disconnected` (the real state arrives later on
/// the event stream). A naive disconnect-then-connect would call start while
/// still disconnecting; reconnect must wait for `disconnected` first.
class _AsyncStopController extends ProxyController {
  ProxyConnectionState _state = ProxyConnectionState.disconnected;
  @override
  ProxyConnectionState get state => _state;
  @override
  TrafficStats get traffic => TrafficStats.zero;
  @override
  ProxyProfile? get activeProfile => _active;
  ProxyProfile? _active;
  @override
  String? get lastError => null;

  final List<String> log = <String>[];

  @override
  void selectProfile(ProxyProfile? profile) => _active = profile;

  @override
  Future<void> connect() async {
    log.add('connect@${_state.name}');
    _state = ProxyConnectionState.connecting;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _state = ProxyConnectionState.connected;
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    // Returns immediately at `disconnecting`; the settled state lands later,
    // exactly like a Network Extension's asynchronous stop.
    _state = ProxyConnectionState.disconnecting;
    notifyListeners();
    Timer(const Duration(milliseconds: 30), () {
      _state = ProxyConnectionState.disconnected;
      notifyListeners();
    });
  }
}

void main() {
  test('reconnect waits for disconnected before starting, ends connected',
      () async {
    final c = _AsyncStopController()
      ..selectProfile(ProxyProfile(
        id: '1',
        name: 'n',
        kind: ProxyKind.vless,
        uri: 'vless://x',
        updatedAt: DateTime(2026),
      ));
    // Bring it up first.
    await c.connect();
    expect(c.state, ProxyConnectionState.connected);
    c.log.clear();

    await c.reconnect();

    // The restart must have started only once the tunnel was fully down.
    expect(c.log, <String>['connect@disconnected']);
    expect(c.state, ProxyConnectionState.connected);
  });

  test('reconnect is a no-op when the tunnel is not up', () async {
    final c = _AsyncStopController();
    await c.reconnect();
    expect(c.log, isEmpty);
    expect(c.state, ProxyConnectionState.disconnected);
  });
}
