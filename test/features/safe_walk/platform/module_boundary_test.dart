import 'package:flutter_test/flutter_test.dart';

import '../../../../tool/check_safe_walk_baseline.dart';

void main() {
  test('M1 composition may inject the four feature modules', () {
    for (final target in [
      'presentation',
      'navigation',
      'safety_data',
      'companion',
    ]) {
      expect(
        allowsSafeWalkDependency(
          'lib/features/safe_walk/platform/integration/root.dart',
          'platform',
          target,
        ),
        isTrue,
      );
    }
  });

  test('ordinary platform adapters cannot import another feature module', () {
    expect(
      allowsSafeWalkDependency(
        'lib/features/safe_walk/platform/native_adapter.dart',
        'platform',
        'companion',
      ),
      isFalse,
    );
  });

  test('feature modules cannot import each other or M1 composition', () {
    for (final target in [
      'platform',
      'navigation',
      'safety_data',
      'companion',
    ]) {
      expect(
        allowsSafeWalkDependency(
          'lib/features/safe_walk/presentation/view.dart',
          'presentation',
          target,
        ),
        isFalse,
      );
    }
  });

  test('a similar directory name is not a composition boundary', () {
    expect(
      allowsSafeWalkDependency(
        'lib/features/safe_walk/platform/integration_backup/root.dart',
        'platform',
        'presentation',
      ),
      isFalse,
    );
  });

  test('own module and shared imports remain available', () {
    expect(
      allowsSafeWalkDependency(
        'lib/features/safe_walk/navigation/route.dart',
        'navigation',
        'navigation',
      ),
      isTrue,
    );
    expect(
      allowsSafeWalkDependency(
        'lib/features/safe_walk/navigation/route.dart',
        'navigation',
        'shared',
      ),
      isTrue,
    );
  });

  test('Windows path separators retain the exact composition boundary', () {
    expect(
      allowsSafeWalkDependency(
        r'lib\features\safe_walk\platform\integration\root.dart',
        'platform',
        'presentation',
      ),
      isTrue,
    );
  });
}
