import 'package:flutter/material.dart';

import '../../theme/nova_radii.dart';
import '../../theme/nova_theme.dart';
import '../../widgets/nova_button.dart';
import '../../widgets/nova_card.dart';
import '../../widgets/nova_logo.dart';

/// First-run onboarding, matching Nova v1.0.0: pick a language, then choose how
/// to start (deploy your own panel, import from a panel, or add a config). Text
/// switches live with the language (and flips to RTL for Persian).
class NovaOnboarding extends StatefulWidget {
  const NovaOnboarding({super.key, required this.onPickLanguage, required this.onFinish});

  /// Apply the chosen locale immediately so the rest of the app follows.
  final void Function(String langCode) onPickLanguage;

  /// action: 'deploy' | 'panel' | 'add' | null (skip).
  final void Function(String? action) onFinish;

  @override
  State<NovaOnboarding> createState() => _NovaOnboardingState();
}

class _NovaOnboardingState extends State<NovaOnboarding> {
  String _lang = 'en';
  int _step = 0;

  bool get _fa => _lang == 'fa';

  String _t(String en, String fa) => _fa ? fa : en;

  @override
  Widget build(BuildContext context) {
    final nova = context.nova;
    return Directionality(
      textDirection: _fa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: NovaSpace.xl, vertical: 48),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 12),
                  const NovaLogo(size: 96),
                  const SizedBox(height: 24),
                  Text(_t('Welcome to Nova', 'به نوا خوش آمدید'),
                      style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(_t('Fast, free, unrestricted internet.', 'اینترنت سریع، رایگان و بدون محدودیت.'),
                      style: TextStyle(color: nova.muted), textAlign: TextAlign.center),
                  const SizedBox(height: 36),
                  if (_step == 0) _languageStep(context, nova) else _startStep(context, nova),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _languageStep(BuildContext context, nova) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(_t('Choose your language', 'زبان خود را انتخاب کنید'),
              style: TextStyle(color: nova.muted, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 12),
        _langTile('en', 'English', nova),
        const SizedBox(height: 10),
        _langTile('fa', 'فارسی', nova),
        const SizedBox(height: 28),
        NovaButton(
          label: _t('Get started', 'شروع کنیم'),
          expand: true,
          onPressed: () => setState(() => _step = 1),
        ),
      ],
    );
  }

  Widget _langTile(String code, String label, nova) {
    final bool sel = _lang == code;
    return NovaCard(
      borderColor: sel ? nova.indigo : null,
      onTap: () {
        setState(() => _lang = code);
        widget.onPickLanguage(code);
      },
      child: Row(
        children: <Widget>[
          Text(label, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 16)),
          const Spacer(),
          if (sel) Icon(Icons.check_circle, color: nova.indigo, size: 20),
        ],
      ),
    );
  }

  Widget _startStep(BuildContext context, nova) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(_t('How would you like to start?', 'چطور می‌خواهید شروع کنید؟'),
            style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(_t('Pick one to get connected. You can change this anytime.',
            'یکی را انتخاب کنید تا وصل شوید. هر زمان می‌توانید تغییرش دهید.'),
            style: TextStyle(color: nova.muted), textAlign: TextAlign.center),
        const SizedBox(height: 22),
        _choice(context, Icons.cloud_upload_outlined,
            _t('Deploy your own panel', 'ساخت پنل اختصاصی'),
            _t('Create a free Cloudflare worker', 'ساخت ورکر رایگان کلودفلر'),
            highlighted: true, onTap: () => widget.onFinish('deploy')),
        const SizedBox(height: 12),
        _choice(context, Icons.login,
            _t('Import from your panel', 'وارد کردن از پنل شما'),
            _t('Sign in and bring your configs', 'ورود و آوردن کانفیگ‌ها'),
            onTap: () => widget.onFinish('panel')),
        const SizedBox(height: 12),
        _choice(context, Icons.add,
            _t('Add a config', 'افزودن کانفیگ'),
            _t('Paste a link or a subscription URL', 'چسباندن لینک یا آدرس اشتراک'),
            onTap: () => widget.onFinish('add')),
        const SizedBox(height: 18),
        TextButton(
          onPressed: () => widget.onFinish(null),
          child: Text(_t("I'll do this later", 'بعداً انجام می‌دهم'), style: TextStyle(color: nova.muted)),
        ),
      ],
    );
  }

  Widget _choice(BuildContext context, IconData icon, String title, String subtitle,
      {bool highlighted = false, required VoidCallback onTap}) {
    final nova = context.nova;
    return NovaCard(
      onTap: onTap,
      borderColor: highlighted ? nova.indigo : null,
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: <Color>[nova.cyan, nova.violet]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, style: TextStyle(color: nova.muted, fontSize: 12)),
              ],
            ),
          ),
          Icon(_fa ? Icons.chevron_left : Icons.chevron_right, color: nova.muted),
        ],
      ),
    );
  }
}
