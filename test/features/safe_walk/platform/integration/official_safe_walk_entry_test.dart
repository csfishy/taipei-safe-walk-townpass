import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/main.dart';
import 'package:town_pass/util/tp_route.dart';
import 'package:town_pass/features/safe_walk/platform/integration/official_safe_walk_entry.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_build.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';

void main() {
  Future<EmailLiveTestTransport> load() async => EmailLiveTestTransport(
    prefs: await SharedPreferences.getInstance(),
    rpc: SupabaseRpcClient(
      config: SafeWalkSupabaseConfig(
        url: Uri.parse('https://example.invalid'),
        apiKey: 'sb_publishable_test',
      ),
    ),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('native preview starts on the wired official route', (
    tester,
  ) async {
    late GetMaterialApp app;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          app = const MyApp().build(context) as GetMaterialApp;
          return const SizedBox();
        },
      ),
    );
    expect(
      app.initialRoute,
      emailLiveTestBuild ? TPRoute.safeWalk : TPRoute.main,
    );
    final entry =
        TPRoute.page.singleWhere((p) => p.name == TPRoute.safeWalk).page()
            as OfficialSafeWalkEntry;
    expect(entry.emailTest, emailLiveTestBuild);
  });

  testWidgets(
    'official preview entry loads email prompt, skip wires same backend',
    (tester) async {
      final transport = await load();
      var flows = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialSafeWalkEntry(
            emailTest: true,
            loadEmailTransport: () async => transport,
            flowBuilder: (backend) {
              expect(backend, same(transport));
              flows++;
              return const Text('official navigation');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('輸入 e-mail 開始 Live 測試'), findsOneWidget);
      expect(flows, 0);
      await tester.tap(find.text('稍後再說'));
      await tester.pumpAndSettle();
      expect(find.text('official navigation'), findsOneWidget);
      expect(transport.hasSession, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('configuration failure is visible and retry never falls back', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OfficialSafeWalkEntry(
          emailTest: true,
          loadEmailTransport: () async {
            if (++attempts == 1) throw StateError('private details');
            return load();
          },
          flowBuilder: (_) => const Text('unexpected fallback'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Live 測試設定無法載入'), findsOneWidget);
    expect(find.textContaining('private details'), findsNothing);
    expect(find.text('unexpected fallback'), findsNothing);
    await tester.tap(find.text('重新載入'));
    await tester.pumpAndSettle();
    expect(find.text('輸入 e-mail 開始 Live 測試'), findsOneWidget);
    expect(attempts, 2);
  });
}
