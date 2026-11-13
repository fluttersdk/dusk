import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/extensions/ext_checkbox.dart';
import 'package:tapir/src/ref_registry.dart';

/// `testWidgets` with the Semantics tree switched on: set_checkbox reads the
/// checked state from it, as it does in a running app where a snapshot has
/// already enabled semantics.
void _testWithSemantics(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      // flutter_test checks for a leaked handle before any addTearDown runs.
      handle.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aiTestSetCheckboxHandler', () {
    setUp(RefRegistry.resetForTesting);

    // -------------------------------------------------------------------------
    // (a) set-true-on-false — checkbox starts unchecked, toggled to checked.
    // -------------------------------------------------------------------------

    _testWithSemantics(
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
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
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

        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['kind'], equals('checked'));
        expect(effect['before'], isFalse);
        expect(effect['after'], isTrue);
        expect(effect['verified'], isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (b) set-false-on-true — checkbox starts checked, toggled to unchecked.
    // -------------------------------------------------------------------------

    _testWithSemantics(
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
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'false'},
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

        // `value` echoes what was requested. `effect.after` is read back off
        // the widget, so a control that ignored the tap is distinguishable
        // from one that took it.
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['kind'], equals('checked'));
        expect(effect['before'], isTrue);
        expect(effect['after'], isFalse);
        expect(effect['verified'], isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (c) Idempotent — no toggle when current value already matches target.
    // -------------------------------------------------------------------------

    _testWithSemantics(
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
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
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

    test('(d) ref not found returns not_found error envelope', () async {
      final response = await aiTestSetCheckboxHandler(
        'ext.tapir.set_checkbox',
        <String, String>{'ref': 'e999', 'value': 'true'},
      );

      expect(response.result, isNull);
      final String detail = response.errorDetail ?? '';
      expect(detail, contains('e999'));
    });

    // -------------------------------------------------------------------------
    // (e) Missing value param — returns missing_param error envelope.
    // -------------------------------------------------------------------------

    test(
      '(e) missing value param returns missing_param error envelope',
      () async {
        final response = await aiTestSetCheckboxHandler(
          'ext.tapir.set_checkbox',
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
          'ext.tapir.set_checkbox',
          const <String, String>{'value': 'true'},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
        expect(response.errorDetail ?? '', contains('ref'));
      },
    );

    test('(g) empty ref string returns missing_param error envelope', () async {
      final response = await aiTestSetCheckboxHandler(
        'ext.tapir.set_checkbox',
        const <String, String>{'ref': '', 'value': 'true'},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('missing required param'));
    });

    test(
      '(h) empty value string returns missing_param error envelope',
      () async {
        final response = await aiTestSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          const <String, String>{'ref': 'e1', 'value': ''},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
      },
    );

    // -------------------------------------------------------------------------
    // (i) Switch widget: a switch reports the toggled flag, not checked, so
    //     this runs the toggled branch of the Semantics read.
    // -------------------------------------------------------------------------

    _testWithSemantics(
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
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        expect(switchValue, isTrue);

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['kind'], equals('checked'));
        expect(effect['before'], isFalse);
        expect(effect['after'], isTrue);
        expect(effect['verified'], isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (j) A control no Material class draws: the state comes from Semantics.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(j) a hand-built control that is already checked is left alone',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int taps = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Semantics(
              container: true,
              checked: true,
              child: GestureDetector(
                onTap: () => taps++,
                child: const SizedBox(width: 40, height: 40),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(GestureDetector));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = RefRegistry.registerForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await aiTestSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['previousValue'], isTrue);
        expect(decoded['toggled'], isFalse);
        expect(taps, 0);
      },
    );

    // -------------------------------------------------------------------------
    // (k) A snapshot ref carries its Semantics node: the read uses it.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(k) a ref registered with its node reads the state and stays idempotent',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int changes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Checkbox(value: true, onChanged: (_) => changes++),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Checkbox));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = RefRegistry.registerForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
          node: tester.getSemantics(find.byType(Checkbox)),
        );

        final response = await aiTestSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['previousValue'], isTrue);
        expect(decoded['value'], isTrue);
        expect(decoded['toggled'], isFalse);
        expect(changes, 0);
      },
    );

    // -------------------------------------------------------------------------
    // (l) A mixed checkbox is neither checked nor unchecked: always tapped.
    // -------------------------------------------------------------------------

    for (final String target in <String>['true', 'false']) {
      _testWithSemantics(
        '(l) a mixed checkbox is tapped once for target $target',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(800, 600);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          int changes = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Checkbox(
                  tristate: true,
                  value: null,
                  onChanged: (_) => changes++,
                ),
              ),
            ),
          );

          final Element element = tester.element(find.byType(Checkbox));
          final RenderBox box = element.findRenderObject()! as RenderBox;
          final String ref = RefRegistry.registerForTesting(
            rect: box.localToGlobal(Offset.zero) & box.size,
            element: element,
            groupId: 'g',
            isTextField: false,
            node: tester.getSemantics(find.byType(Checkbox)),
          );

          final future = aiTestSetCheckboxHandler(
            'ext.tapir.set_checkbox',
            <String, String>{'ref': ref, 'value': target},
          );
          await tester.pump(const Duration(milliseconds: 100));
          await tester.pump();
          await tester.pump();
          final response = await future;

          final Map<String, dynamic> decoded =
              jsonDecode(response.result!) as Map<String, dynamic>;
          expect(decoded['previousValue'], isNull);
          expect(decoded['toggled'], isTrue);
          expect(changes, 1);
          final Map<String, dynamic> effect =
              decoded['effect'] as Map<String, dynamic>;
          expect(effect['before'], isNull);
        },
      );
    }

    // -------------------------------------------------------------------------
    // (m) A labelled container that does not merge: the control inside it.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(m) a ref on a labelled container reads the checked control inside it',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int taps = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Semantics(
              container: true,
              label: 'Accept terms',
              child: Semantics(
                container: true,
                checked: true,
                child: GestureDetector(
                  onTap: () => taps++,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ),
            ),
          ),
        );

        final Finder wrapper = find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == 'Accept terms',
        );
        final Element element = tester.element(wrapper);
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = RefRegistry.registerForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
          node: tester.getSemantics(wrapper),
        );

        // Pumped so a wrong read that taps still completes and fails on the
        // assertions below rather than hanging on the tap's delay.
        final future = aiTestSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['previousValue'], isTrue);
        expect(decoded['toggled'], isFalse);
        expect(taps, 0);
      },
    );

    // -------------------------------------------------------------------------
    // (n) A ref with no checkable state is refused, never guessed at.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(n) a ref on plain text is refused and nothing is tapped',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int taps = 0;
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: GestureDetector(
              onTap: () => taps++,
              child: const Text('Terms of service'),
            ),
          ),
        );

        final Element element = tester.element(find.text('Terms of service'));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = RefRegistry.registerForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNull);
        final Map<String, dynamic> detail =
            jsonDecode(response.errorDetail!) as Map<String, dynamic>;
        expect(
          detail['message'],
          contains('has no checked or toggled state in its Semantics node'),
        );
        expect(taps, 0);
      },
    );

    // -------------------------------------------------------------------------
    // (o) A ref without a node of its own never borrows a sibling's state.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(o) a ref whose nearest node is an ancestor ignores a checked sibling',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const Key decorationKey = ValueKey<String>('decoration');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: <Widget>[
                const SizedBox(key: decorationKey, width: 40, height: 40),
                Semantics(
                  container: true,
                  checked: true,
                  child: const SizedBox(width: 40, height: 40),
                ),
              ],
            ),
          ),
        );

        final Element element = tester.element(find.byKey(decorationKey));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = RefRegistry.registerForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = aiTestSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'false'},
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNull);
        expect(
          response.errorDetail,
          contains('has no checked or toggled state in its Semantics node'),
        );
      },
    );
  });
}
