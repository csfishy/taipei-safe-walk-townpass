import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_setting_view.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

// 只使用明顯虛構的座標（接近 0,0），不是任何真實住家。
Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(390 * 3, 844 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('放大字體仍可讀取圖磚說明與使用儲存控制', (t) async {
    await _pump(
      t,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: SafeWalkHomeSettingView(onSave: (_) async {}, onBack: () {}),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.byType(FlutterMap), findsNothing);
    await t.ensureVisible(find.text('載入地圖'));
    await t.tap(find.text('載入地圖'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('儲存').hitTestable(), findsOneWidget);
  });

  testWidgets('沒有 onHomeChanged 時不顯示設定入口', (t) async {
    await _pump(t, const SafeWalkFlow());
    expect(find.text('設定「家」'), findsNothing);
  });

  testWidgets('第一次：選點後才能儲存，儲存交給 callback', (t) async {
    final saved = <sw.Coordinates?>[];
    await _pump(t, SafeWalkFlow(onHomeChanged: (h) async => saved.add(h)));
    await t.tap(find.text('設定「家」'));
    await t.pumpAndSettle();

    // 尚未選點：儲存不可用。
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    expect(saved, isEmpty);

    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    await t.tap(find.text('載入地圖'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(200, 300));
    await t.pumpAndSettle();
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single, isNotNull);
    // 儲存後回到首頁。
    expect(find.text('點擊開始'), findsOneWidget);
  });

  testWidgets('已設定：顯示編輯與移除，移除回傳 null', (t) async {
    final saved = <sw.Coordinates?>[];
    await _pump(
      t,
      SafeWalkFlow(
        homeLocation: sw.Coordinates(lat: 0.5, lng: 0.5),
        onHomeChanged: (h) async => saved.add(h),
      ),
    );
    expect(find.text('設定「家」'), findsNothing);
    await t.tap(find.text('編輯「家」'));
    await t.pumpAndSettle();
    expect(find.byType(FlutterMap), findsNothing);
    await t.tap(find.text('移除'));
    await t.pumpAndSettle();
    expect(saved, [null]);
  });

  testWidgets('儲存失敗時留在畫面並顯示錯誤，不顯示例外內容', (t) async {
    await _pump(
      t,
      SafeWalkFlow(onHomeChanged: (h) async => throw StateError('secret 0.5')),
    );
    await t.tap(find.text('設定「家」'));
    await t.pumpAndSettle();
    await t.tap(find.text('載入地圖'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(200, 300));
    await t.pumpAndSettle();
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    expect(find.text('儲存失敗，請再試一次。'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });
}
