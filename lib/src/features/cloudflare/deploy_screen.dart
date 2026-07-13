import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/nova_radii.dart';
import '../../theme/nova_theme.dart';
import '../../widgets/nova_button.dart';
import '../../widgets/nova_card.dart';
import '../../widgets/nova_scope.dart';
import 'cloudflare_controller.dart';

/// Deploy a new Nova worker on the connected Cloudflare account: a live timer,
/// a duplicate-name guard, a timeout, and a one-step panel password setup. The
/// deploy state lives on the controller, so leaving this screen never restarts
/// it.
class DeployScreen extends StatefulWidget {
  const DeployScreen({super.key});

  @override
  State<DeployScreen> createState() => _DeployScreenState();
}

class _DeployScreenState extends State<DeployScreen> {
  final TextEditingController _name = TextEditingController(text: 'nova');
  final TextEditingController _password = TextEditingController();
  bool _settingPassword = false;
  bool _panelSaved = false;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  String _fmt(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final CloudflareController cf = NovaScope.of(context).cloudflare;
    final nova = context.nova;
    return Scaffold(
      appBar: AppBar(title: const Text('Deploy your panel')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListenableBuilder(
            listenable: cf,
            builder: (context, _) {
              return ListView(
                padding: const EdgeInsets.all(NovaSpace.xl),
                children: <Widget>[
                  if (!cf.isReady || cf.phase == CfPhase.loading)
                    const Padding(
                      padding: EdgeInsets.only(top: NovaSpace.xxl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  // Deploy needs a Cloudflare session. Reaching this screen from
                  // the empty state doesn't connect first, so gate on it here:
                  // otherwise "Deploy" silently no-ops (the controller returns
                  // early with no session) and looks broken.
                  else if (cf.phase != CfPhase.connected &&
                      cf.phase != CfPhase.working)
                    _connectGate(context, cf, nova)
                  else if (cf.deployResult != null)
                    _result(context, cf, nova)
                  else if (cf.deploying)
                    _deploying(context, cf, nova)
                  else
                    _form(context, cf, nova),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Shown when Deploy is opened without a Cloudflare session. Signs in with the
  /// same in-app OAuth as the Cloudflare screen (external Safari suspends the app
  /// and breaks the loopback redirect).
  Widget _connectGate(BuildContext context, CloudflareController cf, nova) {
    final bool connecting = cf.phase == CfPhase.connecting;
    return NovaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.cloud_outlined, color: nova.cyan, size: 40),
          const SizedBox(height: NovaSpace.md),
          Text('Connect Cloudflare to deploy',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: NovaSpace.sm),
          Text(
              'Sign in to your Cloudflare account once. Nova deploys the worker '
              'onto your own free plan, so it stays yours.',
              style: TextStyle(color: nova.muted)),
          if (cf.error.isNotEmpty) ...<Widget>[
            const SizedBox(height: NovaSpace.md),
            Text(cf.error, style: TextStyle(color: nova.danger)),
          ],
          const SizedBox(height: NovaSpace.lg),
          NovaButton(
            label: connecting ? 'Opening sign-in...' : 'Connect Cloudflare',
            icon: Icons.login,
            expand: true,
            loading: connecting,
            onPressed: () async {
              if (cf.phase == CfPhase.connecting) return;
              await cf.connect((String url) async {
                await launchUrl(Uri.parse(url),
                    mode: LaunchMode.inAppBrowserView);
              }, onRedirect: () async {
                await closeInAppWebView();
              });
              await closeInAppWebView();
            },
          ),
          if (connecting)
            Center(
              child: TextButton(
                onPressed: cf.cancelConnect,
                child: const Text('Cancel'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _form(BuildContext context, CloudflareController cf, nova) {
    return NovaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Spin up your own private Nova worker on your Cloudflare account, free.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: nova.muted)),
          const SizedBox(height: NovaSpace.lg),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Worker name', hintText: 'nova'),
            onChanged: (String v) => _name.text = v.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), ''),
          ),
          if (cf.deployError.isNotEmpty) ...<Widget>[
            const SizedBox(height: NovaSpace.md),
            Text(cf.deployError, style: TextStyle(color: nova.danger)),
          ],
          const SizedBox(height: NovaSpace.lg),
          NovaButton(
            label: 'Deploy',
            icon: Icons.cloud_upload_outlined,
            expand: true,
            onPressed: () {
              final String name = _name.text.trim().isEmpty ? 'nova' : _name.text.trim();
              cf.deploy(name);
            },
          ),
        ],
      ),
    );
  }

  Widget _deploying(BuildContext context, CloudflareController cf, nova) {
    return NovaCard(
      child: Column(
        children: <Widget>[
          const SizedBox(height: NovaSpace.md),
          const CircularProgressIndicator(),
          const SizedBox(height: NovaSpace.lg),
          Text('Deploying${cf.deployProgress.isEmpty ? '' : ': ${cf.deployProgress}'}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: NovaSpace.sm),
          Text(_fmt(cf.deployElapsed), style: TextStyle(color: nova.muted, fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
          const SizedBox(height: NovaSpace.md),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, CloudflareController cf, nova) {
    final String url = cf.deployResult!.workerUrl;
    return NovaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Icon(Icons.check_circle, color: nova.successStrong),
            const SizedBox(width: NovaSpace.sm),
            Text('Worker deployed', style: Theme.of(context).textTheme.titleLarge),
          ]),
          const SizedBox(height: NovaSpace.sm),
          if (url.isNotEmpty)
            SelectableText(url, style: TextStyle(color: nova.cyan)),
          const Divider(height: NovaSpace.xl),
          if (_panelSaved) ...<Widget>[
            Row(children: <Widget>[
              Icon(Icons.verified_user, color: nova.successStrong),
              const SizedBox(width: NovaSpace.sm),
              const Expanded(child: Text('Panel password set and saved.')),
            ]),
          ] else ...<Widget>[
            Text('Set an admin password for your panel', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: NovaSpace.sm),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Panel password'),
            ),
            const SizedBox(height: NovaSpace.md),
            NovaButton(
              label: 'Set password',
              expand: true,
              loading: _settingPassword,
              onPressed: () async {
                if (_password.text.length < 4) return;
                setState(() => _settingPassword = true);
                final bool ok = await cf.setupPassword(url, _password.text);
                if (!mounted) return;
                setState(() {
                  _settingPassword = false;
                  _panelSaved = ok;
                });
              },
            ),
          ],
          const SizedBox(height: NovaSpace.md),
          NovaButton(
            label: 'Done',
            variant: NovaButtonVariant.secondary,
            expand: true,
            onPressed: () {
              cf.resetDeploy();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
