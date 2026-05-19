import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DuskPlugin.aiTestDisableEnvValue = '';
  });

  test('install() registers extensions on first call (counter increments)', () {
    final before = DuskPlugin.installCount;
    DuskPlugin.install();
    expect(DuskPlugin.installCount, equals(before + 1));
  });

  test('install() is idempotent — second call increments counter but no-ops',
      () {
    final before = DuskPlugin.installCount;
    DuskPlugin.install();
    DuskPlugin.install();
    DuskPlugin.install();
    expect(DuskPlugin.installCount, greaterThan(before));
  });

  test('install() skips when DUSK_DISABLE=1', () {
    DuskPlugin.aiTestDisableEnvValue = '1';
    final before = DuskPlugin.installCount;
    DuskPlugin.install();
    expect(DuskPlugin.installCount, equals(before));
  });

  test('install() skips when DUSK_DISABLE=true', () {
    DuskPlugin.aiTestDisableEnvValue = 'true';
    final before = DuskPlugin.installCount;
    DuskPlugin.install();
    expect(DuskPlugin.installCount, equals(before));
  });

  test('install() skips when DUSK_DISABLE=yes', () {
    DuskPlugin.aiTestDisableEnvValue = 'yes';
    final before = DuskPlugin.installCount;
    DuskPlugin.install();
    expect(DuskPlugin.installCount, equals(before));
  });

  test('install() skips when DUSK_DISABLE is mixed case (TRUE / Yes)', () {
    DuskPlugin.aiTestDisableEnvValue = 'TRUE';
    final beforeA = DuskPlugin.installCount;
    DuskPlugin.install();
    expect(DuskPlugin.installCount, equals(beforeA));

    DuskPlugin.aiTestDisableEnvValue = 'Yes';
    final beforeB = DuskPlugin.installCount;
    DuskPlugin.install();
    expect(DuskPlugin.installCount, equals(beforeB));
  });

  test('install() proceeds when DUSK_DISABLE is the empty string', () {
    DuskPlugin.aiTestDisableEnvValue = '';
    final before = DuskPlugin.installCount;
    DuskPlugin.install();
    expect(DuskPlugin.installCount, greaterThan(before));
  });

  test('install() proceeds when DUSK_DISABLE has unrecognized value', () {
    DuskPlugin.aiTestDisableEnvValue = 'no';
    final before = DuskPlugin.installCount;
    DuskPlugin.install();
    expect(DuskPlugin.installCount, greaterThan(before));
  });

  test('enrichers list is mutable and starts shared across the isolate', () {
    final initialLength = DuskPlugin.enrichers.length;
    String? noopEnricher(element, refs) => null;
    DuskPlugin.enrichers.add(noopEnricher);
    expect(DuskPlugin.enrichers.length, equals(initialLength + 1));
    DuskPlugin.enrichers.remove(noopEnricher);
    expect(DuskPlugin.enrichers.length, equals(initialLength));
  });
}
