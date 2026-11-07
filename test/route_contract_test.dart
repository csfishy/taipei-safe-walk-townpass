// The upstream counter template expected a counter that TownPass does not have,
// and booted native services without initialization. Keep a route contract smoke
// test instead; device startup and the official UI still need device validation.
import 'package:flutter_test/flutter_test.dart';
import 'package:town_pass/util/tp_route.dart';

void main() {
  test('official main, account, service editing and WebView routes remain', () {
    final names = TPRoute.page.map((page) => page.name).toList();
    expect(TPRoute.main, '/');
    expect(
      names,
      containsAll([
        TPRoute.main,
        TPRoute.account,
        TPRoute.basicInfo,
        TPRoute.serviceEdit,
        TPRoute.webView,
      ]),
    );
  });
  test('official route names remain unique', () {
    final names = TPRoute.page.map((page) => page.name).toList();
    expect(names.toSet().length, names.length);
  });
}
