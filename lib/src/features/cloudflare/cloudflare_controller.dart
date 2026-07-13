import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nova_cloudflare.dart';
import 'nova_panel.dart';

/// SharedPreferences-backed token store so the Cloudflare login persists.
class SharedPrefsCfStore implements CfStore {
  SharedPrefsCfStore(this._prefs);
  final SharedPreferences _prefs;
  @override
  String get(String key) => _prefs.getString('nova.$key') ?? '';
  @override
  void set(String key, String value) {
    if (value.isEmpty) {
      _prefs.remove('nova.$key');
    } else {
      _prefs.setString('nova.$key', value);
    }
  }
}

enum CfPhase { loading, disconnected, connecting, connected, working }

/// App-scoped controller for the Cloudflare account + Deploy + Panel features.
/// Wraps the ported [NovaCloudflare] and [NovaPanel] clients and exposes their
/// state to the screens. Living above the screens means a deploy keeps running
/// (with its timer) even if the user leaves the page.
class CloudflareController extends ChangeNotifier {
  CfPhase phase = CfPhase.disconnected;
  String accountName = '';
  List<CfWorker> workers = <CfWorker>[];
  int kvCount = 0;
  int d1Count = 0;
  // Worker requests used today vs the free-plan daily allowance. null = not
  // available (not connected, token lacks analytics scope, or no data yet).
  int? workerRequestsToday;
  int workerRequestLimit = NovaCloudflare.freeRequestsPerDay;
  String error = '';
  String message = '';
  String busyWorker = '';

  // Deploy state (survives leaving the Deploy screen).
  bool deploying = false;
  String deployProgress = '';
  int deployElapsed = 0;
  DeployResult? deployResult;
  String deployError = '';

  NovaCloudflare? _cf;
  final NovaPanel _panel = NovaPanel();
  CfSession? _session;
  Timer? _deployTimer;

  void attachPrefs(SharedPreferences prefs) {
    _cf = NovaCloudflare(SharedPrefsCfStore(prefs));
    refresh();
  }

  bool get isReady => _cf != null;

  Future<void> refresh() async {
    final NovaCloudflare? cf = _cf;
    if (cf == null) return;
    _set(phase: CfPhase.loading, error: '');
    try {
      final CfSession? s = await cf.restoreSession();
      if (s == null) {
        _set(phase: CfPhase.disconnected);
        return;
      }
      _session = s;
      await _loadWorkers(s);
    } catch (_) {
      _set(phase: CfPhase.disconnected);
    }
  }

  Future<void> _loadWorkers(CfSession s) async {
    try {
      final List<CfWorker> w = await _cf!.listWorkers(s);
      accountName = s.accountName;
      workers = w;
      _set(phase: CfPhase.connected, error: '');
      final ({int kv, int d1}) counts = await _cf!.resourceCounts(s);
      kvCount = counts.kv;
      d1Count = counts.d1;
      notifyListeners();
      // Usage is best-effort and slower; fetch it after the screen is already
      // usable so it never blocks showing the account.
      workerRequestsToday = await _cf!.workerRequestsToday(s);
      notifyListeners();
    } catch (e) {
      final String msg = e.toString();
      if (msg.contains('401') || msg.contains('403')) {
        _cf!.disconnect();
        _session = null;
        _set(phase: CfPhase.disconnected, error: 'Your Cloudflare session expired. Please connect again.');
      } else {
        accountName = s.accountName;
        _set(phase: CfPhase.connected, error: msg);
      }
    }
  }

  Future<void> connect(
    Future<void> Function(String url) openUrl, {
    Future<void> Function()? onRedirect,
  }) async {
    final NovaCloudflare? cf = _cf;
    if (cf == null) return;
    _set(phase: CfPhase.connecting, error: '');
    try {
      final CfSession s = await cf.connect(openUrl: openUrl, onRedirect: onRedirect);
      _session = s;
      await _loadWorkers(s);
    } catch (e) {
      // A user cancel is not an error — reset quietly to the sign-in screen.
      final bool cancelled = e.toString().toLowerCase().contains('cancel');
      _set(phase: CfPhase.disconnected, error: cancelled ? '' : e.toString());
    }
  }

  /// Aborts an in-flight [connect] when the user backs out of the sign-in sheet,
  /// so the screen returns to its "Connect Cloudflare" state instead of sitting
  /// on "Opening your browser…" until the redirect times out.
  void cancelConnect() {
    _cf?.cancelConnect();
    _set(phase: CfPhase.disconnected, error: '');
  }

  void disconnect() {
    _cf?.disconnect();
    _session = null;
    accountName = '';
    workers = <CfWorker>[];
    kvCount = 0;
    d1Count = 0;
    workerRequestsToday = null;
    _set(phase: CfPhase.disconnected);
  }

  Future<bool> deleteWorker(CfWorker w) async {
    final CfSession? s = _session;
    if (s == null) return false;
    busyWorker = w.name;
    _set(message: '', error: '');
    try {
      await _cf!.deleteWorker(s, w.name);
      busyWorker = '';
      message = 'Worker deleted';
      await _loadWorkers(s);
      return true;
    } catch (e) {
      busyWorker = '';
      _set(error: e.toString());
      return false;
    }
  }

  /// Deploy a new worker. Runs with a live timer and a 120s timeout; the state
  /// stays on the controller so leaving the screen doesn't restart it.
  Future<void> deploy(String name) async {
    final CfSession? s = _session;
    if (s == null || deploying) return;
    deploying = true;
    deployProgress = 'Starting';
    deployElapsed = 0;
    deployResult = null;
    deployError = '';
    notifyListeners();
    _deployTimer?.cancel();
    _deployTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      deployElapsed++;
      notifyListeners();
    });
    try {
      final DeployResult r = await _cf!
          .deploy(s, name, onProgress: (String p) {
            deployProgress = p;
            notifyListeners();
          })
          .timeout(const Duration(seconds: 120));
      deployResult = r;
      deployProgress = 'Done';
      await _loadWorkers(s);
    } on TimeoutException {
      deployError = 'Deploy timed out. Check your connection and try again.';
    } catch (e) {
      deployError = e.toString();
    } finally {
      _deployTimer?.cancel();
      deploying = false;
      notifyListeners();
    }
  }

  void resetDeploy() {
    deployResult = null;
    deployError = '';
    deployProgress = '';
    deployElapsed = 0;
    notifyListeners();
  }

  /// Set a fresh worker's panel password, then verify it.
  Future<bool> setupPassword(String workerUrl, String password) async {
    try {
      final bool configured = await _panel.installConfigured(workerUrl);
      if (!configured) await _panel.installSet(workerUrl, password);
      await _panel.login(workerUrl, password); // verify
      return true;
    } catch (e) {
      _set(error: e.toString());
      return false;
    }
  }

  /// Sign in to a worker's panel and return its importable subscription URL.
  Future<String?> fetchPanelSubscription(String workerUrl, String password) async {
    busyWorker = workerUrl;
    _set(error: '', message: '');
    try {
      final PanelSession ses = await _panel.login(workerUrl, password);
      final String url = await _panel.importableSubscription(ses);
      busyWorker = '';
      notifyListeners();
      return url;
    } catch (e) {
      busyWorker = '';
      _set(error: e.toString());
      return null;
    }
  }

  void _set({CfPhase? phase, String? error, String? message}) {
    if (phase != null) this.phase = phase;
    if (error != null) this.error = error;
    if (message != null) this.message = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _deployTimer?.cancel();
    super.dispose();
  }
}
