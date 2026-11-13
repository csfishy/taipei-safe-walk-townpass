import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:town_pass/features/safe_walk/platform/integration/email_live_test_page.dart';
import 'package:town_pass/features/safe_walk/platform/nearby_emergency/email_live_test_transport.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/safe_walk_supabase_config.dart';
import 'package:town_pass/features/safe_walk/platform/supabase/supabase_rpc_client.dart';

void main() {
  testWidgets(
    'first prompt is explicit, validates email, can skip and return',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final transport = EmailLiveTestTransport(
        prefs: prefs,
        rpc: SupabaseRpcClient(
          config: SafeWalkSupabaseConfig(
            url: Uri.parse('https://example.invalid'),
            apiKey: 'sb_publishable_test',
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EmailLiveTestPage(
            transport: transport,
            flowBuilder: (_) => const Text('existing flow'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('輸入 e-mail 開始 Live 測試'), findsOneWidget);
      expect(find.textContaining('知道該信箱的人也能登入'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.tap(find.text('建立／登入測試帳號'));
      await tester.pump();
      expect(find.text('請輸入有效的 e-mail。'), findsOneWidget);
      await tester.tap(find.text('稍後再說'));
      await tester.pumpAndSettle();
      expect(find.text('existing flow'), findsOneWidget);
      expect(transport.hasSession, isFalse);
      expect(prefs.getBool(EmailLiveTestTransport.seenKey), isTrue);
      await tester.tap(find.text('輸入信箱'));
      await tester.pumpAndSettle();
      expect(find.text('輸入 e-mail 開始 Live 測試'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
