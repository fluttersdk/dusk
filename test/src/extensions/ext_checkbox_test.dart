import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart' show SemanticsNode;
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

  group('tapirSetCheckboxHandler', () {
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
        final String ref = registerRefForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        final response = await _drive(tester, future);

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
        final String ref = registerRefForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'false'},
        );
        final response = await _drive(tester, future);

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['toggled'], isTrue);
        expect(decoded['value'], equals(false));
        expect(decoded['previousValue'], equals(true));

        // `value` and `effect.after` are both read back off the widget, so a
        // control that ignored the tap is distinguishable from one that
        // took it (case (w)).
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
        final String ref = registerRefForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        // Ask to set to true when already true — should be a no-op.
        final response = await tapirSetCheckboxHandler(
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
      final response = await tapirSetCheckboxHandler(
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
        final response = await tapirSetCheckboxHandler(
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
        final response = await tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          const <String, String>{'value': 'true'},
        );
        expect(response.result, isNull);
        expect(response.errorDetail ?? '', contains('missing required param'));
        expect(response.errorDetail ?? '', contains('ref'));
      },
    );

    test('(g) empty ref string returns missing_param error envelope', () async {
      final response = await tapirSetCheckboxHandler(
        'ext.tapir.set_checkbox',
        const <String, String>{'ref': '', 'value': 'true'},
      );
      expect(response.result, isNull);
      expect(response.errorDetail ?? '', contains('missing required param'));
    });

    test(
      '(h) empty value string returns missing_param error envelope',
      () async {
        final response = await tapirSetCheckboxHandler(
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
        final String ref = registerRefForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        final response = await _drive(tester, future);

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
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await tapirSetCheckboxHandler(
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
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
          node: tester.getSemantics(find.byType(Checkbox)),
        );

        final response = await tapirSetCheckboxHandler(
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
          final String ref = registerRefForTesting(
            rect: box.localToGlobal(Offset.zero) & box.size,
            element: element,
            groupId: 'g',
            isTextField: false,
            node: tester.getSemantics(find.byType(Checkbox)),
          );

          final future = tapirSetCheckboxHandler(
            'ext.tapir.set_checkbox',
            <String, String>{'ref': ref, 'value': target},
          );
          final response = await _drive(tester, future);

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
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
          node: tester.getSemantics(wrapper),
        );

        // Pumped so a wrong read that taps still completes and fails on the
        // assertions below rather than hanging on the tap's delay.
        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        final response = await _drive(tester, future);

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
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        final response = await _drive(tester, future);

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
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'false'},
        );
        final response = await _drive(tester, future);

        expect(response.result, isNull);
        expect(
          response.errorDetail,
          contains('has no checked or toggled state in its Semantics node'),
        );
      },
    );

    // -------------------------------------------------------------------------
    // (p) Inside a merged group the ref names the group: Flutter folds the
    //     checked flag of the sibling into the group's node, so the ancestor's
    //     own flags cannot be told apart from it. A tap that changes nothing
    //     is reported as `verified: false`, never as success.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(p) a ref inside a merged group reads the group and reports an '
      'unverified tap',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const Key decorationKey = ValueKey<String>('decoration');
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: MergeSemantics(
              child: Column(
                children: <Widget>[
                  const SizedBox(key: decorationKey, width: 40, height: 40),
                  Semantics(
                    checked: true,
                    child: const SizedBox(width: 40, height: 40),
                  ),
                ],
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byKey(decorationKey));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'false'},
        );
        final response = await _drive(tester, future);

        // The group reads as checked, so asking for unchecked taps once; the
        // decoration cannot toggle anything, and the read-back says so.
        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['previousValue'], isTrue);
        expect(decoded['toggled'], isTrue);
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['before'], isTrue);
        expect(effect['after'], isTrue);
        expect(effect['verified'], isFalse);
      },
    );

    // -------------------------------------------------------------------------
    // (q) A labelled container holding several controls names none of them:
    //     tapping its centre would toggle whichever control sits there, not
    //     the one whose state was read.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(q) a ref on a container holding three switches is refused and no '
      'switch changes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final List<bool> values = <bool>[false, false, false];
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Semantics(
                  container: true,
                  label: 'Notifications',
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < values.length; i++)
                        SwitchListTile(
                          title: Text('Channel $i'),
                          value: values[i],
                          onChanged: (v) => setState(() => values[i] = v),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final Finder wrapper = find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == 'Notifications',
        );
        final Element element = tester.element(wrapper);
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
          node: tester.getSemantics(wrapper),
        );

        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        final response = await _drive(tester, future);

        expect(response.result, isNull);
        final Map<String, dynamic> detail =
            jsonDecode(response.errorDetail!) as Map<String, dynamic>;
        expect(
          detail['message'],
          contains('holds more than one checkbox, switch or radio'),
        );
        expect(values, equals(<bool>[false, false, false]));
      },
    );

    // -------------------------------------------------------------------------
    // (r) A labelled container holding exactly one control: the tap goes to
    //     that control's own rect, not to the container's centre.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(r) a ref on a container holding one switch toggles that switch even '
      'when the container centre is elsewhere',
      (WidgetTester tester) async {
        // A device pixel ratio of 2: the semantics root transform carries it,
        // and a tap target left in physical pixels lands off the switch.
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool wifi = false;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Semantics(
                  container: true,
                  label: 'Wi-Fi',
                  child: Row(
                    children: <Widget>[
                      const Text('Wi-Fi'),
                      const SizedBox(width: 500, height: 48),
                      // A list tile merges its switch into a node of its
                      // own, so the container keeps no toggled flag.
                      SizedBox(
                        width: 200,
                        child: SwitchListTile(
                          title: const Text('On'),
                          value: wifi,
                          onChanged: (v) => setState(() => wifi = v),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final Finder wrapper = find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == 'Wi-Fi',
        );
        final Element element = tester.element(wrapper);
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final Rect rect = box.localToGlobal(Offset.zero) & box.size;
        final Rect switchRect = tester.getRect(find.byType(SwitchListTile));
        expect(
          switchRect.contains(rect.center),
          isFalse,
          reason: 'the container centre must miss the switch',
        );
        final String ref = registerRefForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
          node: tester.getSemantics(wrapper),
        );

        final future = tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': ref, 'value': 'true'},
        );
        final response = await _drive(tester, future);

        expect(wifi, isTrue);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['previousValue'], isFalse);
        expect(decoded['toggled'], isTrue);
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['after'], isTrue);
        expect(effect['verified'], isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (s) A bare Switch inside a labelled container: the Switch is no
    //     semantics boundary, so its toggled flag lands on the container's
    //     node. The tap still has to reach the switch, not the container
    //     centre.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(s) a bare Switch whose flag sits on its labelled container toggles '
      'the switch, not the container centre',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool dark = false;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Semantics(
                  container: true,
                  label: 'Dark mode',
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 500, height: 48),
                      Switch(
                        value: dark,
                        onChanged: (v) => setState(() => dark = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final Finder wrapper = find.byWidgetPredicate(
          (Widget widget) =>
              widget is Semantics && widget.properties.label == 'Dark mode',
        );
        final Element element = tester.element(wrapper);
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final Rect rect = box.localToGlobal(Offset.zero) & box.size;
        expect(
          tester.getRect(find.byType(Switch)).contains(rect.center),
          isFalse,
          reason: 'the container centre must miss the switch',
        );
        final SemanticsNode node = tester.getSemantics(wrapper);
        expect(
          node.getSemanticsData().flagsCollection.isToggled,
          isNot(Tristate.none),
          reason: 'the toggled flag must sit on the container node itself',
        );
        final String ref = registerRefForTesting(
          rect: rect,
          element: element,
          groupId: 'g',
          isTextField: false,
          node: node,
        );

        final response = await _drive(
          tester,
          tapirSetCheckboxHandler('ext.tapir.set_checkbox', <String, String>{
            'ref': ref,
            'value': 'true',
          }),
        );

        expect(dark, isTrue);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['verified'], isTrue);
      },
    );

    // -------------------------------------------------------------------------
    // (t) The actionability gate runs on the control: one below the fold is
    //     scrolled into view before the tap, and one under an overlay is
    //     refused with the gate's reason.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(t) a checkbox below the fold is scrolled into view and toggled',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool accepted = false;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      const SizedBox(height: 2000),
                      Checkbox(
                        value: accepted,
                        onChanged: (v) => setState(() => accepted = v!),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Checkbox));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await _drive(
          tester,
          tapirSetCheckboxHandler('ext.tapir.set_checkbox', <String, String>{
            'ref': ref,
            'value': 'true',
          }),
        );

        expect(accepted, isTrue);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['verified'], isTrue);
      },
    );

    _testWithSemantics(
      '(u) a checkbox under an overlay is refused with the gate reason and '
      'left alone',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool accepted = false;
        int overlayTaps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: Stack(
                  children: <Widget>[
                    Checkbox(
                      value: accepted,
                      onChanged: (v) => setState(() => accepted = v!),
                    ),
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => overlayTaps++,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Checkbox));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await _drive(
          tester,
          tapirSetCheckboxHandler('ext.tapir.set_checkbox', <String, String>{
            'ref': ref,
            'value': 'true',
          }),
        );

        expect(response.result, isNull);
        final Map<String, dynamic> detail =
            jsonDecode(response.errorDetail!) as Map<String, dynamic>;
        expect(detail['message'], contains('obscured by other widget'));
        expect(
          (detail['envelope'] as Map<String, dynamic>)['type'],
          equals('obscured'),
        );
        expect(accepted, isFalse);
        expect(overlayTaps, 0);
      },
    );

    // -------------------------------------------------------------------------
    // (v) A value that is not a boolean is refused before anything is read
    //     or tapped: "flase" used to count as true.
    // -------------------------------------------------------------------------

    for (final String bad in <String>['flase', 'yes', 'TRUE', '2']) {
      test('(v) value "$bad" is refused as an invalid parameter', () async {
        final response = await tapirSetCheckboxHandler(
          'ext.tapir.set_checkbox',
          <String, String>{'ref': 'e1', 'value': bad},
        );

        expect(response.result, isNull);
        expect(
          response.errorCode,
          equals(developer.ServiceExtensionResponse.invalidParams),
        );
        final Map<String, dynamic> detail =
            jsonDecode(response.errorDetail!) as Map<String, dynamic>;
        expect(detail['message'], contains('"$bad"'));
        expect(
          (detail['envelope'] as Map<String, dynamic>)['type'],
          equals('invalid_param'),
        );
      });
    }

    for (final MapEntry<String, bool> accepted in <String, bool>{
      'true': true,
      '1': true,
      'false': false,
      '0': false,
    }.entries) {
      _testWithSemantics(
        '(v) value "${accepted.key}" reads as ${accepted.value}',
        (WidgetTester tester) async {
          bool? checked = accepted.value;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Checkbox(value: checked, onChanged: (v) => checked = v),
              ),
            ),
          );
          final Element element = tester.element(find.byType(Checkbox));
          final RenderBox box = element.findRenderObject()! as RenderBox;
          final String ref = registerRefForTesting(
            rect: box.localToGlobal(Offset.zero) & box.size,
            element: element,
            groupId: 'g',
            isTextField: false,
          );

          final response = await tapirSetCheckboxHandler(
            'ext.tapir.set_checkbox',
            <String, String>{'ref': ref, 'value': accepted.key},
          );

          final Map<String, dynamic> decoded =
              jsonDecode(response.result!) as Map<String, dynamic>;
          expect(decoded['toggled'], isFalse, reason: 'already matches');
          expect(decoded['value'], equals(accepted.value));
        },
      );
    }

    // -------------------------------------------------------------------------
    // (w) `value` is the state read back after the tap, not the request: a
    //     control whose owner ignores the change reports what it shows.
    // -------------------------------------------------------------------------

    _testWithSemantics(
      '(w) a checkbox that ignores the tap reports the value it kept',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int changes = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Checkbox(value: false, onChanged: (_) => changes++),
            ),
          ),
        );

        final Element element = tester.element(find.byType(Checkbox));
        final RenderBox box = element.findRenderObject()! as RenderBox;
        final String ref = registerRefForTesting(
          rect: box.localToGlobal(Offset.zero) & box.size,
          element: element,
          groupId: 'g',
          isTextField: false,
        );

        final response = await _drive(
          tester,
          tapirSetCheckboxHandler('ext.tapir.set_checkbox', <String, String>{
            'ref': ref,
            'value': 'true',
          }),
        );

        expect(changes, 1, reason: 'the tap reached the checkbox');
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['value'], isFalse);
        final Map<String, dynamic> effect =
            decoded['effect'] as Map<String, dynamic>;
        expect(effect['after'], isFalse);
        expect(effect['verified'], isFalse);
      },
    );
  });
}

/// Pumps frames until [future] completes, so a handler that awaits frames
/// and timers (the gate's stable check, the tap's 50 ms hold) finishes
/// under the fake clock whatever its number of waits.
Future<T> _drive<T>(WidgetTester tester, Future<T> future) async {
  bool done = false;
  unawaited(future.whenComplete(() => done = true));
  for (int i = 0; i < 100 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  return future;
}
