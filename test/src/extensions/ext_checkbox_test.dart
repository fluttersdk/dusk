import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_checkbox.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aiTestSetCheckboxHandler', () {
    setUp(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (a) set-true-on-false — checkbox starts unchecked, toggled to checked.
    // -------------------------------------------------------------------------

    testWidgets(
      '(a) set-true-on-false: toggles unchecked checkbox to checked',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool checkValue = false;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Checkbox(
                  value: checkValue,
                  onChanged: (v) => setState(() => checkValue = v ?? false),
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Checkbox));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final Rect rect = box.localToGlobal(Offset.zero) & box.size;
        final String ref = RefRegistry.registerForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          <String, String>{
            'ref': ref,
            'value': 'true',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ref'], equals(ref));
        expect(decoded['toggled'], isTrue);
        expect(decoded['value'], equals(true));
        expect(decoded['previousValue'], equals(false));
      },
    );

    // -------------------------------------------------------------------------
    // (b) set-false-on-true — checkbox starts checked, toggled to unchecked.
    // -------------------------------------------------------------------------

    testWidgets(
      '(b) set-false-on-true: toggles checked checkbox to unchecked',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool checkValue = true;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Checkbox(
                  value: checkValue,
                  onChanged: (v) => setState(() => checkValue = v ?? true),
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Checkbox));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final Rect rect = box.localToGlobal(Offset.zero) & box.size;
        final String ref = RefRegistry.registerForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          <String, String>{
            'ref': ref,
            'value': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['toggled'], isTrue);
        expect(decoded['value'], equals(false));
        expect(decoded['previousValue'], equals(true));
      },
    );

    // -------------------------------------------------------------------------
    // (c) Idempotent — no toggle when current value already matches target.
    // -------------------------------------------------------------------------

    testWidgets(
      '(c) idempotent: no toggle when checkbox already matches target value',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool checkValue = true;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Checkbox(
                  value: checkValue,
                  onChanged: (v) => setState(() => checkValue = v ?? true),
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Checkbox));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final Rect rect = box.localToGlobal(Offset.zero) & box.size;
        final String ref = RefRegistry.registerForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        // Ask to set to true when already true — should be a no-op.
        final response = await aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          <String, String>{
            'ref': ref,
            'value': 'true',
          },
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['toggled'], isFalse);
        expect(decoded['value'], equals(true));
        expect(decoded['previousValue'], equals(true));
      },
    );

    // -------------------------------------------------------------------------
    // (d) Ref not found — returns not_found error envelope.
    // -------------------------------------------------------------------------

    test(
      '(d) ref not found returns not_found error envelope',
      () async {
        final response = await aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          <String, String>{
            'ref': 'e999',
            'value': 'true',
          },
        );

        expect(response.result, isNull);
        final String detail = response.errorDetail ?? '';
        expect(detail, contains('e999'));
      },
    );

    // -------------------------------------------------------------------------
    // (e) Missing value param — returns missing_param error envelope.
    // -------------------------------------------------------------------------

    test(
      '(e) missing value param returns missing_param error envelope',
      () async {
        final response = await aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          <String, String>{'ref': 'e1'},
        );

        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
      },
    );

    // -------------------------------------------------------------------------
    // (f) Missing ref param — empty/null ref returns missing_param error.
    // -------------------------------------------------------------------------

    test(
      '(f) missing ref param returns missing_param error envelope',
      () async {
        final response = await aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          const <String, String>{'value': 'true'},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
        expect(response.errorDetail ?? '', contains('ref'));
      },
    );

    test(
      '(g) empty ref string returns missing_param error envelope',
      () async {
        final response = await aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          const <String, String>{'ref': '', 'value': 'true'},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
      },
    );

    test(
      '(h) empty value string returns missing_param error envelope',
      () async {
        final response = await aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          const <String, String>{'ref': 'e1', 'value': ''},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
      },
    );

    // -------------------------------------------------------------------------
    // (i) Switch widget — exercises _checkboxValueFromElement's Switch branch
    //     so the Switch-specific value extraction path runs.
    // -------------------------------------------------------------------------

    testWidgets(
      '(i) set-true-on-false on a Switch widget toggles correctly',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool switchValue = false;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Switch(
                  value: switchValue,
                  onChanged: (v) => setState(() => switchValue = v),
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Switch));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final Rect rect = box.localToGlobal(Offset.zero) & box.size;
        final String ref = RefRegistry.registerForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestSetCheckboxHandler(
          'ext.dusk.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        expect(switchValue, isTrue);
      },
    );
  });
}
