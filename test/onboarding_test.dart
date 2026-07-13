import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_client/src/app.dart';
import 'package:nova_client/src/core/proxy/conn_info_controller.dart';
import 'package:nova_client/src/core/proxy/mock_proxy_controller.dart';
import 'package:nova_client/src/features/cloudflare/cloudflare_controller.dart';
import 'package:nova_client/src/features/profiles/profiles_controller.dart';
import 'package:nova_client/src/features/radar/radar_controller.dart';
import 'package:nova_client/src/features/settings/settings_controller.dart';
import 'package:nova_client/src/theme/theme_controller.dart';

void main() {
  testWidgets('first run shows onboarding, then the how-to-start step', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController()..attachPrefs(prefs);
    final profiles = ProfilesController()..attachPrefs(prefs);
    final radar = RadarController()..attachPrefs(prefs);
    final cloudflare = CloudflareController()..attachPrefs(prefs);

    final proxy = MockProxyController();
    await tester.pumpWidget(NovaApp(
      theme: theme,
      proxy: proxy,
      connInfo: ConnInfoController(proxy),
      profiles: profiles,
      radar: radar,
      cloudflare: cloudflare,
      settings: SettingsController(prefs: prefs),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Nova'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();

    expect(find.text('How would you like to start?'), findsOneWidget);
    expect(find.text('Deploy your own panel'), findsOneWidget);
  });
}
