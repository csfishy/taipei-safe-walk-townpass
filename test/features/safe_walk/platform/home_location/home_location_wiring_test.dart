import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/platform/home_location/home_location_service.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_composition_root.dart';
import 'package:town_pass/features/safe_walk/platform/integration/safe_walk_route_speaker.dart';
import 'package:town_pass/features/safe_walk/presentation/safe_walk_flow.dart';
import 'package:town_pass/features/safe_walk/shared/models/safe_walk_models.dart'
    as sw;

class _Store implements HomeLocationStore {
  final loaded = Completer<String?>();
  @override
  Future<String?> read() => loaded.future;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> clear() async {}
}

class _Speaker implements SafeWalkRouteSpeaker {
  @override
  bool get available => false;
  @override
  void speak(String text, {void Function()? onDone}) {}
  @override
  void stop() {}
  @override
  void setLifecycleActive(bool active) {}
  @override
  Future<void> stopForEmergency() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('遲到的初次讀取不覆蓋使用者剛儲存的家', (tester) async {
    final store = _Store();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SafeWalkCompositionRoot(
          homeLocationStore: store,
          speaker: _Speaker(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    var flow = tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
    await flow.onHomeChanged!(sw.Coordinates(lat: 0.5, lng: 0.75));
    await tester.pump();
    store.loaded.complete('{"lat":1.5,"lng":1.75}');
    await tester.pumpAndSettle();
    flow = tester.widget<SafeWalkFlow>(find.byType(SafeWalkFlow));
    expect(flow.homeLocation!.lat, 0.5);
    expect(flow.homeLocation!.lng, 0.75);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
