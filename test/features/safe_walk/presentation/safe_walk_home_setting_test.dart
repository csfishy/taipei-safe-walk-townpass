import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_home_setting_view.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_map_view.dart';
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

/// 家的設定在「安心行設定」裡：先從首頁齒輪進入，再點項目。
Future<void> _tapInSettings(WidgetTester t, String label) async {
  await t.tap(find.byTooltip('安心行設定'));
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Live 未設定家時不送示範座標，提示先設定家', (t) async {
    final asked = <sw.Coordinates>[];
    await _pump(
      t,
      SafeWalkFlow(mode: sw.DataMode.live, onPlanRoute: asked.add),
    );
    await t.tap(find.text('點擊開始'));
    await t.pumpAndSettle();
    await t.tap(find.text('目的地'));
    await t.pumpAndSettle();
    expect(asked, isEmpty);
    expect(find.text('請先返回首頁設定「家」的位置，再規劃回家路線。'), findsWidgets);
    expect(
      t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).routeState.path,
      isNull,
    );
  });

  testWidgets('Live 移除家後不回到示範家規劃', (t) async {
    final asked = <sw.Coordinates>[];
    sw.Coordinates? home = sw.Coordinates(lat: 0.5, lng: 0.75);
    await _pump(
      t,
      StatefulBuilder(
        builder: (context, setParentState) => SafeWalkFlow(
          mode: sw.DataMode.live,
          homeLocation: home,
          onHomeChanged: (next) async => setParentState(() => home = next),
          onPlanRoute: asked.add,
        ),
      ),
    );
    await _tapInSettings(t, '編輯「家」');
    await t.pumpAndSettle();
    await t.tap(find.text('移除'));
    await t.pumpAndSettle();
    expect(home, isNull);
    // 移除後回到「安心行設定」，再回首頁。
    await t.tap(find.byTooltip('返回'));
    await t.pumpAndSettle();
    await t.tap(find.text('點擊開始'));
    await t.pumpAndSettle();
    await t.tap(find.text('目的地'));
    await t.pumpAndSettle();
    expect(asked, isEmpty);
    // 切換目的地後，才請使用者在地圖上點選家。
    expect(find.text('家在哪裡？'), findsOneWidget);
    expect(
      t.widget<SafeWalkMapView>(find.byType(SafeWalkMapView)).routeState.path,
      isNull,
    );
  });

  testWidgets('Live 設定家後只傳入已儲存的家座標', (t) async {
    final asked = <sw.Coordinates>[];
    await _pump(
      t,
      SafeWalkFlow(
        mode: sw.DataMode.live,
        homeLocation: sw.Coordinates(lat: 0.5, lng: 0.75),
        onPlanRoute: asked.add,
      ),
    );
    await t.tap(find.text('點擊開始'));
    await t.pumpAndSettle();
    await t.tap(find.text('目的地'));
    await t.pumpAndSettle();
    expect(asked, hasLength(1));
    expect(asked.single.lat, 0.5);
    expect(asked.single.lng, 0.75);
    expect(find.text('請先返回首頁設定「家」的位置，再規劃回家路線。'), findsNothing);
  });

  testWidgets('放大字體仍可讀取圖磚說明與使用儲存控制', (t) async {
    await _pump(
      t,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: SafeWalkHomeSettingView(onSave: (_) async {}, onBack: () {}),
      ),
    );
    expect(t.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('載入地圖'), findsNothing);
    expect(find.textContaining('檢視範圍與 IP'), findsOneWidget);
    expect(find.text('儲存').hitTestable(), findsOneWidget);
  });

  testWidgets('沒有 onHomeChanged 時不顯示設定入口', (t) async {
    await _pump(t, const SafeWalkFlow());
    expect(find.text('設定「家」'), findsNothing);
  });

  testWidgets('第一次：選點後才能儲存，儲存交給 callback', (t) async {
    final saved = <sw.Coordinates?>[];
    await _pump(t, SafeWalkFlow(onHomeChanged: (h) async => saved.add(h)));
    await _tapInSettings(t, '設定「家」');
    await t.pumpAndSettle();

    // 尚未選點：儲存不可用。
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    expect(saved, isEmpty);

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('載入地圖'), findsNothing);
    expect(
      find.text('© OpenStreetMap contributors · Protomaps'),
      findsOneWidget,
    );
    await t.tapAt(const Offset(200, 300));
    await t.pumpAndSettle();
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();

    expect(saved, hasLength(1));
    expect(saved.single, isNotNull);
    // 儲存後回到「安心行設定」。
    expect(find.text('安心行設定'), findsOneWidget);
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
    await _tapInSettings(t, '編輯「家」');
    await t.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('載入地圖'), findsNothing);
    await t.tap(find.text('移除'));
    await t.pumpAndSettle();
    expect(saved, [null]);
  });

  testWidgets('編輯時直接載入儲存的家，無需確認即可儲存', (t) async {
    final saved = <sw.Coordinates?>[];
    await _pump(
      t,
      SafeWalkFlow(
        homeLocation: sw.Coordinates(lat: 0.5, lng: 0.75),
        onHomeChanged: (h) async => saved.add(h),
      ),
    );
    await _tapInSettings(t, '編輯「家」');
    await t.pumpAndSettle();
    final map = t.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.options.initialCenter.latitude, 0.5);
    expect(map.options.initialCenter.longitude, 0.75);
    expect(find.text('載入地圖'), findsNothing);
    expect(find.textContaining('範圍可能包含已儲存的家'), findsOneWidget);
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    expect(saved.single?.lat, 0.5);
    expect(saved.single?.lng, 0.75);
    expect(find.text('安心行設定'), findsOneWidget);
  });

  testWidgets('儲存失敗時留在畫面並顯示錯誤，不顯示例外內容', (t) async {
    await _pump(
      t,
      SafeWalkFlow(onHomeChanged: (h) async => throw StateError('secret 0.5')),
    );
    await _tapInSettings(t, '設定「家」');
    await t.pumpAndSettle();
    await t.tapAt(const Offset(200, 300));
    await t.pumpAndSettle();
    await t.tap(find.text('儲存'));
    await t.pumpAndSettle();
    expect(find.text('儲存失敗，請再試一次。'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });
}
