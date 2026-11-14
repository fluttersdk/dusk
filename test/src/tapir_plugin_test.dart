import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/tapir_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TapirPlugin.aiTestDisableEnvValue = '';
  });

  test('install() registers extensions on first call (counter increments)', () {
    final before = TapirPlugin.installCount;
    TapirPlugin.install();
    expect(TapirPlugin.installCount, equals(before + 1));
  });

  test(
    'install() is idempotent — second call increments counter but no-ops',
    () {
      final before = TapirPlugin.installCount;
      TapirPlugin.install();
      TapirPlugin.install();
      TapirPlugin.install();
      expect(TapirPlugin.installCount, greaterThan(before));
    },
  );

  test('install() skips when TAPIR_DISABLE=1', () {
    TapirPlugin.aiTestDisableEnvValue = '1';
    final before = TapirPlugin.installCount;
    TapirPlugin.install();
    expect(TapirPlugin.installCount, equals(before));
  });

  test('install() skips when TAPIR_DISABLE=true', () {
    TapirPlugin.aiTestDisableEnvValue = 'true';
    final before = TapirPlugin.installCount;
    TapirPlugin.install();
    expect(TapirPlugin.installCount, equals(before));
  });

  test('install() skips when TAPIR_DISABLE=yes', () {
    TapirPlugin.aiTestDisableEnvValue = 'yes';
    final before = TapirPlugin.installCount;
    TapirPlugin.install();
    expect(TapirPlugin.installCount, equals(before));
  });

  test('install() skips when TAPIR_DISABLE is mixed case (TRUE / Yes)', () {
    TapirPlugin.aiTestDisableEnvValue = 'TRUE';
    final beforeA = TapirPlugin.installCount;
    TapirPlugin.install();
    expect(TapirPlugin.installCount, equals(beforeA));

    TapirPlugin.aiTestDisableEnvValue = 'Yes';
    final beforeB = TapirPlugin.installCount;
    TapirPlugin.install();
    expect(TapirPlugin.installCount, equals(beforeB));
  });

  test('install() proceeds when TAPIR_DISABLE is the empty string', () {
    TapirPlugin.aiTestDisableEnvValue = '';
    final before = TapirPlugin.installCount;
    TapirPlugin.install();
    expect(TapirPlugin.installCount, greaterThan(before));
  });

  test('install() proceeds when TAPIR_DISABLE has unrecognized value', () {
    TapirPlugin.aiTestDisableEnvValue = 'no';
    final before = TapirPlugin.installCount;
    TapirPlugin.install();
    expect(TapirPlugin.installCount, greaterThan(before));
  });

  test('enrichers list is mutable and starts shared across the isolate', () {
    final initialLength = TapirPlugin.enrichers.length;
    String? noopEnricher(element, refs) => null;
    TapirPlugin.enrichers.add(noopEnricher);
    expect(TapirPlugin.enrichers.length, equals(initialLength + 1));
    TapirPlugin.enrichers.remove(noopEnricher);
    expect(TapirPlugin.enrichers.length, equals(initialLength));
  });

  group('semantics handle', () {
    tearDown(TapirPlugin.resetSemanticsForTesting);

    test(
      'acquire is idempotent and release reports whether it dropped one',
      () {
        TapirPlugin.resetSemanticsForTesting();
        expect(TapirPlugin.acquireSemantics(), isTrue);
        expect(TapirPlugin.acquireSemantics(), isFalse);
        expect(TapirPlugin.releaseSemantics(), isTrue);
        expect(TapirPlugin.semanticsReleased, isTrue);
        expect(TapirPlugin.releaseSemantics(), isFalse);
      },
    );

    test('acquire clears the released flag', () {
      TapirPlugin.resetSemanticsForTesting();
      TapirPlugin.acquireSemantics();
      TapirPlugin.releaseSemantics();
      TapirPlugin.acquireSemantics();
      expect(TapirPlugin.semanticsReleased, isFalse);
    });
  });
}
