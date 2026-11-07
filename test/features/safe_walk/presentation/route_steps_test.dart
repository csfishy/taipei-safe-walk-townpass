import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/features/safe_walk/presentation/mock/safe_walk_demo_data.dart';

// 文字路線用相對轉彎（左轉／右轉），不是東西南北。
void main() {
  const a = LatLng(25.1000, 121.5300);
  const north = LatLng(25.1010, 121.5300); // 約 110 m 往北
  test('往北後往東＝右轉；往北後往西＝左轉', () {
    expect(routeSteps(const [a, north, LatLng(25.1010, 121.5310)]).map((s) => s.turn), [StepTurn.start, StepTurn.right]);
    expect(routeSteps(const [a, north, LatLng(25.1010, 121.5290)]).map((s) => s.turn), [StepTurn.start, StepTurn.left]);
  });
  test('小角度不算轉彎，距離合併', () {
    final steps = routeSteps(const [a, LatLng(25.1005, 121.5301), north]);
    expect(steps.map((s) => s.turn), [StepTurn.start]);
    expect(steps.single.meters, 110);
  });
  test('往回走＝迴轉', () {
    expect(routeSteps(const [a, north, a]).map((s) => s.turn), [StepTurn.start, StepTurn.uTurn]);
  });
}
