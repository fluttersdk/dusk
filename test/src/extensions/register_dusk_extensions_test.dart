import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/register_dusk_extensions.dart';

/// Asserts that `registerAllDuskExtensions()` wires the three alpha-2
/// aggregator entries added in Wave 2 (Steps 6 / 9 / 10) — navigation,
/// evaluate, close_app — alongside the alpha-1 entries. Steps 7 (press_key)
/// and 8 (select_option) register inside the pre-existing
/// `registerTextInputExtensions()` / `registerScrollExtensions()` so they do
/// NOT surface as new aggregator calls.
///
/// Implemented as a grep-the-source test because the alternative (symbol
/// resolution) would re-register the VM Service extensions inside the test
/// isolate and trip the idempotency guard's "registered after first
/// reload" warning. Source-level verification is sufficient: the file is
/// load-bearing for the plugin's install path; either the call site is
/// present in source, or it is not.
void main() {
  group('registerAllDuskExtensions() aggregator wiring', () {
    late String source;

    setUpAll(() {
      final file = File(
        'lib/src/extensions/register_dusk_extensions.dart',
      );
      expect(
        file.existsSync(),
        isTrue,
        reason: 'aggregator source file missing at ${file.path}',
      );
      source = file.readAsStringSync();
    });

    test('calls registerNavigationExtensions() (Step 6)', () {
      expect(
        source,
        contains('registerNavigationExtensions();'),
        reason: 'aggregator must call registerNavigationExtensions() so the '
            'ext.dusk.navigate / navigate_back / get_routes extensions '
            'register on DuskPlugin.install()',
      );
    });

    test('calls registerEvaluateExtension() (Step 9)', () {
      expect(
        source,
        contains('registerEvaluateExtension();'),
        reason: 'aggregator must call registerEvaluateExtension() so the '
            'ext.dusk.evaluate extension registers on DuskPlugin.install()',
      );
    });

    test('calls registerCloseAppExtension() (Step 10)', () {
      expect(
        source,
        contains('registerCloseAppExtension();'),
        reason: 'aggregator must call registerCloseAppExtension() so the '
            'ext.dusk.close_app extension registers on DuskPlugin.install()',
      );
    });

    test('imports ext_navigation.dart, ext_evaluate.dart, ext_close_app.dart',
        () {
      expect(source, contains("import 'ext_navigation.dart';"));
      expect(source, contains("import 'ext_evaluate.dart';"));
      expect(source, contains("import 'ext_close_app.dart';"));
    });

    test('preserves the pre-existing alpha-1 aggregator calls', () {
      expect(source, contains('registerSnapExtension();'));
      expect(source, contains('registerPointerExtensions();'));
      expect(source, contains('registerTextInputExtensions();'));
      expect(source, contains('registerScrollExtensions();'));
      expect(source, contains('registerScreenshotExtension();'));
      expect(source, contains('registerWaitFindExtensions();'));
      expect(source, contains('registerModalRouterExtension();'));
    });
  });

  group('registerAllDuskExtensions execution', () {
    test('invokes every sub-register without throwing (hot-restart safe)', () {
      registerAllDuskExtensions();
      registerAllDuskExtensions();
    });
  });
}
