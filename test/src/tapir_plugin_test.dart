import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/tapir_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => debugTapirDisabledOverride = null);

  test('install() registers extensions on first call (counter increments)', () {
    final before = tapirInstallCount;
    TapirPlugin.install();
    expect(tapirInstallCount, equals(before + 1));
  });

  test(
    'install() is idempotent: a second call increments the counter but no-ops',
    () {
      final before = tapirInstallCount;
      TapirPlugin.install();
      TapirPlugin.install();
      TapirPlugin.install();
      expect(tapirInstallCount, greaterThan(before));
    },
  );

  group('TapirPlugin.isDisabled', () {
    test('is false in a build without --dart-define=TAPIR_DISABLE', () {
      expect(TapirPlugin.isDisabled, isFalse);
    });

    test('install() skips while disabled and installs once enabled', () {
      debugTapirDisabledOverride = true;
      expect(TapirPlugin.isDisabled, isTrue);
      final before = tapirInstallCount;
      TapirPlugin.install();
      expect(tapirInstallCount, equals(before));

      debugTapirDisabledOverride = false;
      TapirPlugin.install();
      expect(tapirInstallCount, greaterThan(before));
    });

    for (final String value in <String>['1', 'true', 'yes', 'TRUE', ' Yes ']) {
      test('the define value "$value" disables tapir', () {
        expect(tapirDisableValueDisables(value), isTrue);
      });
    }

    for (final String value in <String>['', '0', 'no', 'false', 'off']) {
      test('the define value "$value" leaves tapir on', () {
        expect(tapirDisableValueDisables(value), isFalse);
      });
    }
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
    tearDown(resetTapirSemanticsForTesting);

    test(
      'acquire is idempotent and release reports whether it dropped one',
      () {
        resetTapirSemanticsForTesting();
        expect(acquireTapirSemantics(), isTrue);
        expect(acquireTapirSemantics(), isFalse);
        expect(releaseTapirSemantics(), isTrue);
        expect(tapirSemanticsReleased, isTrue);
        expect(releaseTapirSemantics(), isFalse);
      },
    );

    test('acquire clears the released flag', () {
      resetTapirSemanticsForTesting();
      acquireTapirSemantics();
      releaseTapirSemantics();
      acquireTapirSemantics();
      expect(tapirSemanticsReleased, isFalse);
    });
  });
}
