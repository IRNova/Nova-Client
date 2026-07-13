import 'package:flutter/material.dart';

import '../../theme/nova_theme.dart';
import 'nova_panel.dart';

/// Full panel admin editor for a deployed worker: connection info, the editable
/// config flags, the network/routing/DNS/WARP settings, and the custom clean-IP
/// list. Mirrors the native Android PanelAdminScreens so the panel has the same
/// controls on iOS. Opened with the worker URL + admin password already known.
class PanelAdminScreen extends StatefulWidget {
  const PanelAdminScreen({
    super.key,
    required this.workerUrl,
    required this.password,
    required this.title,
  });

  final String workerUrl;
  final String password;
  final String title;

  @override
  State<PanelAdminScreen> createState() => _PanelAdminScreenState();
}

class _PanelAdminScreenState extends State<PanelAdminScreen> {
  final NovaPanel _panel = NovaPanel();
  PanelSession? _session;
  Whoami? _whoami;
  Map<String, dynamic> _config = <String, dynamic>{};
  Map<String, dynamic> _net = <String, dynamic>{};
  late final TextEditingController _ipsCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  String _saving = ''; // '', 'config', 'net', 'ips'

  // Editable config flags (HOST/UUID are read-only server-side).
  static const List<(String, String)> _configToggles = <(String, String)>[
    ('tlsFragment', 'TLS fragment'),
    ('skipCertVerify', 'Skip cert verify'),
    ('enable0RTT', '0-RTT'),
    ('randomPath', 'Random path'),
  ];

  // network-settings.json toggles, in the native order.
  static const List<(String, String)> _netToggles = <(String, String)>[
    ('enableRouting', 'Routing rules'),
    ('enableAdBlock', 'Block ads'),
    ('enableMalwareBlock', 'Block malware'),
    ('enablePhishingBlock', 'Block phishing'),
    ('blockQUIC', 'Block QUIC'),
    ('enableDomesticBypass', 'Bypass Iran sites'),
    ('bypassChina', 'Bypass China'),
    ('bypassRussia', 'Bypass Russia'),
    ('bypassSanctions', 'Bypass sanctioned sites'),
    ('enableDoH', 'Secure DNS (DoH)'),
    ('enableIPv6', 'IPv6'),
    ('allowLAN', 'Allow LAN'),
    ('enableWarp', 'WARP'),
  ];

  static const List<String> _dohProviders = <String>[
    'cloudflare',
    'google',
    'quad9',
    'adguard',
  ];
  static const List<String> _warpModes = <String>['warp', 'chain', 'wow'];
  static const List<String> _logLevels = <String>[
    'debug',
    'info',
    'warn',
    'error',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ipsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final PanelSession s =
          await _panel.login(widget.workerUrl, widget.password);
      final Map<String, dynamic> config = await _panel.getConfig(s);
      final Map<String, dynamic> net = await _panel.getNetworkSettings(s);
      String ips = "";
      try {
        ips = await _panel.getIPs(s);
      } catch (_) {/* ADD.txt may be empty/absent */}
      Whoami? who;
      try {
        who = await _panel.whoami(s);
      } catch (_) {/* best-effort */}
      if (!mounted) return;
      setState(() {
        _session = s;
        _config = config;
        _net = net;
        _ipsCtrl.text = ips;
        _whoami = who;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is PanelException ? e.message : e.toString();
      });
    }
  }

  Future<void> _saveConfig() async {
    final PanelSession? s = _session;
    if (s == null) return;
    setState(() => _saving = 'config');
    try {
      await _panel.saveConfig(s, _config);
      _toast('Config saved');
    } catch (e) {
      _toast(e is PanelException ? e.message : 'Save failed');
    } finally {
      if (mounted) setState(() => _saving = '');
    }
  }

  Future<void> _saveNet() async {
    final PanelSession? s = _session;
    if (s == null) return;
    setState(() => _saving = 'net');
    try {
      await _panel.saveNetworkSettings(s, _net);
      _toast('Network settings saved');
    } catch (e) {
      _toast(e is PanelException ? e.message : 'Save failed');
    } finally {
      if (mounted) setState(() => _saving = '');
    }
  }

  Future<void> _saveIps() async {
    final PanelSession? s = _session;
    if (s == null) return;
    setState(() => _saving = 'ips');
    try {
      await _panel.saveIPs(s, _ipsCtrl.text);
      _toast('Custom IPs saved');
    } catch (e) {
      _toast(e is PanelException ? e.message : 'Save failed');
    } finally {
      if (mounted) setState(() => _saving = '');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _flag(Map<String, dynamic> m, String k) => m[k] == true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          if (!_loading)
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: _sections(),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.error_outline, color: context.nova.danger, size: 40),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  List<Widget> _sections() {
    final nova = context.nova;
    return <Widget>[
      if (_whoami != null) _whoamiCard(_whoami!),
      _card(
        'Config',
        <Widget>[
          _readonly('HOST', _config['HOST']?.toString() ?? ''),
          _readonly('UUID', _config['UUID']?.toString() ?? ''),
          for (final (String, String) t in _configToggles)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(t.$2),
              value: _flag(_config, t.$1),
              onChanged: (bool v) => setState(() => _config[t.$1] = v),
            ),
        ],
        saving: _saving == 'config',
        onSave: _saveConfig,
      ),
      _card(
        'Network & routing',
        <Widget>[
          for (final (String, String) t in _netToggles)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(t.$2),
              value: _flag(_net, t.$1),
              onChanged: (bool v) => setState(() => _net[t.$1] = v),
            ),
          if (_flag(_net, 'enableDoH'))
            _dropdown('DoH provider', 'dohProvider', _dohProviders),
          if (_flag(_net, 'enableWarp'))
            _dropdown('WARP mode', 'warpMode', _warpModes),
          _dropdown('Log level', 'logLevel', _logLevels),
          _number('Monthly cap (GB, 0 = off)', 'monthlyCapGB'),
          _number('Speed limit (KB/s, 0 = off)', 'speedLimitKBps'),
        ],
        saving: _saving == 'net',
        onSave: _saveNet,
      ),
      _card(
        'Custom clean IPs',
        <Widget>[
          Text('One IP or host per line. Used to stamp fresh exits.',
              style: TextStyle(color: nova.muted, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _ipsCtrl,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '104.16.0.0\n104.17.0.0',
            ),
          ),
        ],
        saving: _saving == 'ips',
        onSave: _saveIps,
      ),
    ];
  }

  Widget _whoamiCard(Whoami w) {
    final nova = context.nova;
    final List<String> bits = <String>[
      if (w.isp.isNotEmpty) w.isp,
      if (w.asn != 0) 'AS${w.asn}',
      if (w.city.isNotEmpty || w.country.isNotEmpty)
        <String>[w.city, w.country].where((String s) => s.isNotEmpty).join(', '),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.public_rounded, color: nova.cyan),
            const SizedBox(width: 12),
            Expanded(
              child: Text(bits.isEmpty ? 'Connected' : bits.join('  ·  '),
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children,
      {required bool saving, required VoidCallback onSave}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (saving)
                  const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  TextButton.icon(
                    onPressed: onSave,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _readonly(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
                width: 64,
                child: Text(label,
                    style: TextStyle(color: context.nova.muted, fontSize: 13))),
            Expanded(
              child: SelectableText(value.isEmpty ? '—' : value,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 12)),
            ),
          ],
        ),
      );

  Widget _dropdown(String label, String key, List<String> options) {
    final String current = (_net[key]?.toString() ?? '').isNotEmpty
        ? _net[key].toString()
        : options.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          DropdownButton<String>(
            value: options.contains(current) ? current : options.first,
            items: options
                .map((String o) =>
                    DropdownMenuItem<String>(value: o, child: Text(o)))
                .toList(),
            onChanged: (String? v) {
              if (v != null) setState(() => _net[key] = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _number(String label, String key) {
    final int value = (_net[key] is num) ? (_net[key] as num).toInt() : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label)),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: '$value',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.end,
              decoration: const InputDecoration(isDense: true),
              onChanged: (String v) =>
                  _net[key] = int.tryParse(v.trim()) ?? 0,
            ),
          ),
        ],
      ),
    );
  }
}
