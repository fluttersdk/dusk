library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_text_input.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// D2 regression tests: collapse nested `textbox` Semantics nodes via
/// render-object CONTAINMENT and annotate the surviving node `typeable: true`.
///
/// Background: a wind `WInput` wraps as
/// `Semantics(textField:true) > MergeSemantics > TextField`. `RenderEditable`
/// unconditionally owns its own `textField` Semantics node (flutter#26336) and
/// `MergeSemantics` cannot absorb it (flutter#160281), so the tree carries TWO
/// nested `textbox` nodes. Before this fix dusk minted two `eN` refs; agents
/// naturally target the inner leaf, and `dusk:type` on it throws -32000.
///
/// The fix threads the nearest enclosing textbox render object down through
/// `_emitNode`. When a `textbox` node's render object is a DESCENDANT of an
/// ancestor textbox's render object, the inner ref is suppressed and only the
/// outer typeable node is emitted, carrying a `typeable: true` marker.
///
/// Collapse is by CONTAINMENT only, never label/value equality: two sibling
/// fields sharing a label must remain two distinct refs (the inner render
/// object of one is never a descendant of the other's render object).
///
/// ## Test harness note
///
/// `duskSnapBuild` walks `rootPipelineOwner` AND every child pipeline owner;
/// in the Flutter test harness the real widget tree lives under a child owner,
/// so the snapshot string is populated. Drive it via
/// `tester.runAsync(() => duskSnapBuild())` (mirrors the overflow test in
/// `ext_snapshot_dispatcher_test.dart`).

/// Counts the `[ref=` occurrences across the whole snapshot YAML.
int _countRefs(String snapshot) => 'ref='.allMatches(snapshot).length;

/// Counts the distinct `textbox` role lines in the snapshot YAML.
int _countTextboxLines(String snapshot) => snapshot
    .split('\n')
    .where((String line) => line.trimLeft().startsWith('- textbox'))
    .length;

void main() {
  setUp(RefRegistry.resetForTesting);
  tearDown(RefRegistry.resetForTesting);

  group('ext.dusk.snap textbox containment collapse', () {
    testWidgets(
      '(a) Semantics(textField) > MergeSemantics > TextField collapses to '
      'ONE textbox ref carrying typeable: true',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 1. Pump the exact wind WInput shape: an outer textField Semantics
        //    wrapper around a MergeSemantics around a real TextField (whose
        //    RenderEditable owns a second textField node).
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Semantics(
                textField: true,
                label: 'Email',
                child: const MergeSemantics(
                  child: TextField(
                    decoration: InputDecoration(hintText: 'you@example.com'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // 2. Capture the snapshot via the child-owner-aware build path.
        final Map<String, dynamic> payload = await tester.runAsync(
          () => duskSnapBuild(),
        ) as Map<String, dynamic>;
        final String snapshot = payload['snapshot'] as String;

        // 3. Exactly one textbox ref survives; the inner ref is suppressed.
        expect(
          _countTextboxLines(snapshot),
          1,
          reason: 'nested textbox nodes must collapse to a single textbox line',
        );
        expect(
          _countRefs(snapshot),
          1,
          reason: 'only the surviving outer textbox node mints a ref',
        );

        // 4. The surviving node is annotated typeable: true.
        expect(
          snapshot,
          contains('typeable: true'),
          reason: 'the surviving typeable textbox carries a typeable marker',
        );
      },
    );

    testWidgets(
      '(a) dusk:type on the surviving collapsed ref succeeds',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Semantics(
                textField: true,
                label: 'Email',
                child: MergeSemantics(
                  child: TextField(controller: controller),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // 1. Build the snapshot so the surviving textbox is registered as a ref.
        await tester.runAsync(() => duskSnapBuild());

        // 2. The single registered ref must be the outer (typeable) node, whose
        //    element subtree hosts the EditableText. typeIntoElement walks
        //    descendants, so typing resolves the inner EditableTextState.
        final RefEntry? entry = RefRegistry.lookup('e1');
        expect(
          entry,
          isNotNull,
          reason: 'the surviving collapsed textbox must be registered as e1',
        );

        await tester.runAsync(
          () =>
              typeIntoElement(element: entry!.element, text: 'hello@dusk.dev'),
        );
        await tester.pump();

        expect(
          controller.text,
          'hello@dusk.dev',
          reason:
              'typing on the surviving ref must reach the inner EditableText',
        );
      },
    );

    testWidgets(
      '(b) two sibling fields sharing the same label remain TWO distinct refs',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 1. Two WInput-shaped siblings under the SAME label. Containment can
        //    never collapse these: neither inner render object is a descendant
        //    of the other's render object.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  Semantics(
                    textField: true,
                    label: 'Code',
                    child: MergeSemantics(
                      child: TextField(),
                    ),
                  ),
                  Semantics(
                    textField: true,
                    label: 'Code',
                    child: MergeSemantics(
                      child: TextField(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        final Map<String, dynamic> payload = await tester.runAsync(
          () => duskSnapBuild(),
        ) as Map<String, dynamic>;
        final String snapshot = payload['snapshot'] as String;

        // 2. Each sibling collapses its own inner node, leaving two textbox
        //    refs (no false-collapse on shared label).
        expect(
          _countTextboxLines(snapshot),
          2,
          reason: 'shared-label siblings must NOT collapse into each other',
        );
        expect(
          _countRefs(snapshot),
          2,
          reason: 'two independent fields keep two distinct refs',
        );
      },
    );

    testWidgets(
      '(c) a label-bearing field (outer label, inner placeholder) resolves to '
      'the typeable node',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final TextEditingController controller = TextEditingController();
        addTearDown(controller.dispose);

        // 1. Outer label differs from inner placeholder/value.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Semantics(
                textField: true,
                label: 'Full name',
                child: MergeSemantics(
                  child: TextField(
                    controller: controller,
                    decoration:
                        const InputDecoration(hintText: 'Jane Appleseed'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final Map<String, dynamic> payload = await tester.runAsync(
          () => duskSnapBuild(),
        ) as Map<String, dynamic>;
        final String snapshot = payload['snapshot'] as String;

        // 2. One typeable textbox survives, carrying the outer label.
        expect(_countTextboxLines(snapshot), 1);
        expect(snapshot, contains('typeable: true'));
        expect(
          snapshot,
          contains('textbox "Full name"'),
          reason: 'the surviving node keeps the outer human-readable label',
        );

        // 3. The single ref types into the inner field.
        final RefEntry? entry = RefRegistry.lookup('e1');
        expect(entry, isNotNull);
        await tester.runAsync(
          () => typeIntoElement(element: entry!.element, text: 'Jane'),
        );
        await tester.pump();
        expect(controller.text, 'Jane');
      },
    );

    testWidgets(
      'triple-nested textboxes collapse to one ref; suppressed nodes still '
      'walk their children',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 1. Outer textbox -> inner textbox -> TextField (RenderEditable adds a
        //    third textbox node). The middle textbox is suppressed AND still
        //    has the RenderEditable textbox as a child, so the suppression
        //    branch must recurse through it. All three collapse to one ref.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Semantics(
                textField: true,
                label: 'Token',
                child: Semantics(
                  textField: true,
                  child: const MergeSemantics(
                    child: TextField(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final Map<String, dynamic> payload = await tester.runAsync(
          () => duskSnapBuild(),
        ) as Map<String, dynamic>;
        final String snapshot = payload['snapshot'] as String;

        expect(
          _countTextboxLines(snapshot),
          1,
          reason: 'all nested textboxes collapse to a single surviving node',
        );
        expect(_countRefs(snapshot), 1);
        expect(snapshot, contains('typeable: true'));
        expect(
          snapshot,
          contains('textbox "Token"'),
          reason: 'the outermost textbox is the survivor',
        );
      },
    );

    testWidgets(
      'non-textbox interactive nodes keep the existing line format unchanged',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () {},
                child: const Text('Submit'),
              ),
            ),
          ),
        );
        await tester.pump();

        final Map<String, dynamic> payload = await tester.runAsync(
          () => duskSnapBuild(),
        ) as Map<String, dynamic>;
        final String snapshot = payload['snapshot'] as String;

        // A button must NOT gain a typeable marker and keeps its ref.
        expect(snapshot, contains('button "Submit"'));
        expect(snapshot, isNot(contains('typeable: true')));
        expect(_countRefs(snapshot), 1);
      },
    );
  });
}
