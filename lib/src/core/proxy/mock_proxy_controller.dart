import 'dart:async';
import 'dart:math';

import '../models/proxy_profile.dart';
import 'proxy_controller.dart';

/// A fully-interactive [ProxyController] that simulates the connection
/// lifecycle and a live traffic graph. This drives the dashboard end-to-end so
/// the UI can be developed and reviewed before the native sing-box core lands.
class MockProxyController extends ProxyController {
  MockProxyController();

  final Random _rng = Random();

  ProxyConnectionState _state = ProxyConnectionState.disconnected;
  @override
  ProxyConnectionState get state => _state;

  TrafficStats _traffic = TrafficStats.zero;
  @override
  TrafficStats get traffic => _traffic;

  ProxyProfile? _active;
  @override
  ProxyProfile? get activeProfile => _active;

  String? _lastError;
  @override
  String? get lastError => _lastError;

  Timer? _ticker;
  int _upTotal = 0;
  int _downTotal = 0;

  @override
  void selectProfile(ProxyProfile? profile) {
    _active = profile;
    notifyListeners();
  }

  @override
  Future<void> connect() async {
    if (_state.isActive || _state.isBusy) return;
    if (_active == null) {
      _lastError = 'No profile selected';
      _state = ProxyConnectionState.error;
      notifyListeners();
      return;
    }
    _lastError = null;
    _state = ProxyConnectionState.connecting;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 900));

    _state = ProxyConnectionState.connected;
    _upTotal = 0;
    _downTotal = 0;
    _startTicker();
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    if (_state == ProxyConnectionState.disconnected) return;
    _state = ProxyConnectionState.disconnecting;
    notifyListeners();

    await Future<void>.delayed(const Duration(milliseconds: 400));

    _stopTicker();
    _traffic = TrafficStats.zero;
    _state = ProxyConnectionState.disconnected;
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // Plausible bursty throughput.
      final double down = 40000 + _rng.nextDouble() * 1800000;
      final double up = 8000 + _rng.nextDouble() * 220000;
      _downTotal += down.round();
      _upTotal += up.round();
      _traffic = TrafficStats(
        downlinkBps: down,
        uplinkBps: up,
        downlinkTotal: _downTotal,
        uplinkTotal: _upTotal,
      );
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
