import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/proxy_profile.dart';

/// Owns the user's connection profiles (single links + subscriptions) and
/// persists them. Karing-style clients revolve around this list; the dashboard
/// connects to whichever profile is active.
class ProfilesController extends ChangeNotifier {
  ProfilesController({SharedPreferences? prefs}) : _prefs = prefs {
    _load();
  }

  static const String _kProfilesKey = 'nova.profiles';
  static const String _kActiveKey = 'nova.profiles.active';

  SharedPreferences? _prefs;

  final List<ProxyProfile> _profiles = <ProxyProfile>[];
  List<ProxyProfile> get profiles => List<ProxyProfile>.unmodifiable(_profiles);

  String? _activeId;
  String? get activeId => _activeId;

  ProxyProfile? get active {
    if (_activeId == null) return null;
    for (final p in _profiles) {
      if (p.id == _activeId) return p;
    }
    return null;
  }

  void attachPrefs(SharedPreferences prefs) {
    _prefs = prefs;
    _load();
    notifyListeners();
  }

  void _load() {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(_kProfilesKey);
    _profiles.clear();
    if (raw != null) {
      try {
        _profiles.addAll(ProxyProfile.decodeList(raw));
      } catch (_) {}
    }
    _pruneBrokenDemos();
    final String? savedActive = prefs.getString(_kActiveKey);
    _activeId =
        (savedActive != null && _profiles.any((p) => p.id == savedActive))
            ? savedActive
            : (_profiles.isNotEmpty ? _profiles.first.id : null);
  }

  /// Earlier builds seeded two placeholder profiles that can never connect: a
  /// "subscription" pointing at the marketing site (which serves HTML, not a
  /// node list) and a `vless://example` stub. Both surfaced on connect as
  /// "Unsupported or invalid profile link", so strip them from any install that
  /// still carries them. New installs start empty and prompt for a real link.
  void _pruneBrokenDemos() {
    final int before = _profiles.length;
    _profiles.removeWhere((ProxyProfile p) =>
        p.id == 'demo-sub' ||
        p.id == 'demo-vless' ||
        p.subscriptionUrl == 'https://novaproxy.online/sub' ||
        p.uri.trim() == 'vless://example');
    if (_profiles.length != before) {
      // Persist the cleanup so it only runs once.
      _prefs?.setString(_kProfilesKey, ProxyProfile.encodeList(_profiles));
    }
  }

  void setActive(String id) {
    _activeId = id;
    notifyListeners();
    _prefs?.setString(_kActiveKey, id);
  }

  void add(ProxyProfile profile) {
    _profiles.add(profile);
    _activeId ??= profile.id;
    notifyListeners();
    _persist();
  }

  void remove(String id) {
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) {
      _activeId = _profiles.isNotEmpty ? _profiles.first.id : null;
      if (_activeId != null) _prefs?.setString(_kActiveKey, _activeId!);
    }
    notifyListeners();
    _persist();
  }

  void update(ProxyProfile profile) {
    final idx = _profiles.indexWhere((p) => p.id == profile.id);
    if (idx < 0) return;
    _profiles[idx] = profile;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    await _prefs?.setString(_kProfilesKey, ProxyProfile.encodeList(_profiles));
  }
}
