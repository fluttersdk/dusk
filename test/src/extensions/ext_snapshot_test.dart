import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/extensions/ext_snapshot.dart';
import 'package:tapir/src/ref_registry.dart';

import '../../_support/merged_stage.dart';

const String _unbalancedLabel = 'Container Sample (MP4, H.264';

Widget _button(String label) {
  return Semantics(
    container: true,
    button: true,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: const SizedBox(width: 160, height: 40),
    ),
  );
}

/// An 800x600 view holding a normal button, one pushed 5000px off the right
/// edge, and one with an opaque layer stacked above it.
Widget _visibilityScreen() {
  return MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[_button('Visible'), _button('Covered')],
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Transform.translate(
              offset: const Offset(5000, 0),
              child: _button('Away'),
            ),
          ),
          Positioned(
            left: 0,
            top: 40,
            width: 160,
            height: 40,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    ),
  );
}

void _useSmallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _lineFor(String snapshot, String label) {
  return snapshot
      .split('\n')
      .firstWhere((String line) => line.contains('"$label"'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tapirSnapBuild', () {
    setUp(() {
      RefRegistry.resetForTesting();
      resetSnapshotBaselineForTesting();
    });
    tearDown(() {
      RefRegistry.resetForTesting();
      resetSnapshotBaselineForTesting();
    });

    group('snapshotForAction() with an unknown mode', () {
      Widget screen() {
        return MaterialApp(
          home: Scaffold(body: _button('Create monitor')),
        );
      }

      testWidgets('is read case-insensitively', (WidgetTester tester) async {
        await tester.pumpWidget(screen());

        final Map<String, dynamic> payload =
            await snapshotForAction(<String, String>{'snapshot': ' Diff '});

        expect(payload['snapshotMode'], equals('diff'));
      });

      testWidgets('is reported in the payload instead of dropped', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(screen());

        final Map<String, dynamic> payload =
            await snapshotForAction(<String, String>{'snapshot': 'delta'});

        expect(payload.containsKey('snapshot'), isFalse);
        expect(payload['snapshotError'], contains('"delta"'));
        expect(payload['snapshotError'], contains('full, diff or none'));
      });
    });

    group('snapshot baseline', () {
      Widget screen() {
        return MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[_button('Create monitor'), _button('Other')],
            ),
          ),
        );
      }

      testWidgets('is empty before the first snapshot', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(screen());

        expect(snapshotBaseline, isNull);
      });

      testWidgets('an unfiltered walk records its own text', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(screen());

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;

        expect(snapshotBaseline, equals(snapshot));
      });

      testWidgets('a later unfiltered walk replaces the baseline', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(screen());
        await tapirSnapBuild();

        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: _button('Create monitor'))),
        );
        final String second = (await tapirSnapBuild())['snapshot'] as String;

        expect(snapshotBaseline, equals(second));
      });

      testWidgets('a filtered walk leaves the baseline alone', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(screen());
        final String full = (await tapirSnapBuild())['snapshot'] as String;

        final String grepped =
            (await tapirSnapBuild(grep: 'Create'))['snapshot'] as String;
        await tapirSnapBuild(maxDepth: 0);
        await tapirSnapBuild(interactiveOnly: true);

        expect(grepped, isNot(equals(full)));
        expect(snapshotBaseline, equals(full));
      });

      testWidgets('a filtered walk does not seed an empty baseline', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(screen());

        await tapirSnapBuild(grep: 'Create');

        expect(snapshotBaseline, isNull);
      });

      testWidgets('a walk with enrichers does not record', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(screen());

        await tapirSnapBuild(includeEnrichers: true);

        expect(snapshotBaseline, isNull);
      });
    });

    group('grep', () {
      testWidgets(
          'falls back to a literal match when the pattern is not a regex', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  _button(_unbalancedLabel),
                  _button('Something else'),
                ],
              ),
            ),
          ),
        );

        final Map<String, dynamic> payload =
            await tapirSnapBuild(grep: _unbalancedLabel);
        final String snapshot = payload['snapshot'] as String;

        expect(snapshot, contains(_unbalancedLabel));
        expect(snapshot, isNot(contains('Something else')));
        expect(payload['grepLiteral'], isTrue);
      });

      testWidgets('a valid regex behaves as before and carries no flag', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  _button('Create monitor'),
                  _button('Delete monitor'),
                  _button('Unrelated'),
                ],
              ),
            ),
          ),
        );

        final Map<String, dynamic> payload =
            await tapirSnapBuild(grep: 'Create|Delete');
        final String snapshot = payload['snapshot'] as String;

        expect(snapshot, contains('Create monitor'));
        expect(snapshot, contains('Delete monitor'));
        expect(snapshot, isNot(contains('Unrelated')));
        expect(payload.containsKey('grepLiteral'), isFalse);
      });

      testWidgets('the extension reports the literal fallback too', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: _button(_unbalancedLabel)),
          ),
        );

        final developer.ServiceExtensionResponse response =
            await tapirSnapHandler(
          'ext.tapir.snap',
          const <String, String>{'grep': _unbalancedLabel},
        );

        expect(response.errorDetail, isNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['snapshot'], contains(_unbalancedLabel));
        expect(decoded['grepLiteral'], isTrue);
      });
    });

    group('visibility markers', () {
      testWidgets('flags a ref-bearing node outside the viewport', (
        WidgetTester tester,
      ) async {
        _useSmallView(tester);
        await tester.pumpWidget(_visibilityScreen());

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;

        expect(_lineFor(snapshot, 'Away'), endsWith(' [offscreen]'));
        expect(_lineFor(snapshot, 'Away'),
            matches(r'\[ref=e\d+\] \[offscreen\]$'));
        expect(_lineFor(snapshot, 'Visible'), isNot(contains('[offscreen]')));
      });

      testWidgets('flags a node whose centre is covered by another widget', (
        WidgetTester tester,
      ) async {
        _useSmallView(tester);
        await tester.pumpWidget(_visibilityScreen());

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;

        expect(_lineFor(snapshot, 'Covered'), endsWith(' [occluded]'));
        expect(_lineFor(snapshot, 'Visible'), isNot(contains('[occluded]')));
        expect(_lineFor(snapshot, 'Away'), isNot(contains('[occluded]')));
      });

      testWidgets('does not flag a node whose own container claims its centre',
          (
        WidgetTester tester,
      ) async {
        // The container is not painted above the node, so nothing covers it,
        // even though the gate refuses to tap it (the tap would reach the
        // container instead).
        _useSmallView(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  child: Semantics(
                    container: true,
                    button: true,
                    label: 'Inside',
                    onTap: () {},
                    child: const SizedBox(width: 160, height: 40),
                  ),
                ),
              ),
            ),
          ),
        );

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;

        expect(_lineFor(snapshot, 'Inside'), matches(r'\[ref=e\d+\]$'));
      });

      testWidgets('leaves a healthy screen byte-identical', (
        WidgetTester tester,
      ) async {
        _useSmallView(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _button('Save'),
                  const Text('Saved'),
                ],
              ),
            ),
          ),
        );

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;

        expect(snapshot, equals('- button "Save" [ref=e1]\n- text "Saved"\n'));
      });
    });

    group('ref bindings', () {
      testWidgets('binds a labelled ref to its label, index and count', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  _button('Save'),
                  _button('Cancel'),
                  _button('Save'),
                ],
              ),
            ),
          ),
        );

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;
        final List<String> saveRefs = RegExp(r'"Save" \[ref=(e\d+)\]')
            .allMatches(snapshot)
            .map((RegExpMatch m) => m.group(1)!)
            .toList();
        final String cancelRef =
            RegExp(r'"Cancel" \[ref=(e\d+)\]').firstMatch(snapshot)!.group(1)!;

        expect(saveRefs, hasLength(2));
        for (int i = 0; i < saveRefs.length; i++) {
          final RefBinding? binding = RefRegistry.lookupBinding(saveRefs[i]);
          expect(binding, isNotNull);
          expect(binding!.query.semanticsLabel, equals('Save'));
          expect(binding.query.matchIndex, equals(i));
          expect(binding.matchCount, equals(2));
        }
        final RefBinding? cancel = RefRegistry.lookupBinding(cancelRef);
        expect(cancel!.query.semanticsLabel, equals('Cancel'));
        expect(cancel.query.matchIndex, equals(0));
        expect(cancel.matchCount, equals(1));
      });

      testWidgets('binds a labelled ref to the route it lives on', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: _button('Save')),
          ),
        );

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;
        final String ref =
            RegExp(r'"Save" \[ref=(e\d+)\]').firstMatch(snapshot)!.group(1)!;
        final Route<dynamic>? expected =
            ModalRoute.of(tester.element(find.byType(Scaffold)));

        expect(expected, isNotNull);
        expect(
          RefRegistry.lookupBinding(ref)!.route?.target,
          same(expected),
        );
      });

      testWidgets('binds no route when the ref lives outside a navigator', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: _button('Save'),
            ),
          ),
        );

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;
        final String ref =
            RegExp(r'"Save" \[ref=(e\d+)\]').firstMatch(snapshot)!.group(1)!;

        final RefBinding? binding = RefRegistry.lookupBinding(ref);
        expect(binding, isNotNull);
        expect(binding!.route, isNull);
      });

      testWidgets('leaves a label-less ref unbound', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Semantics(
                container: true,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox(width: 160, height: 40),
                ),
              ),
            ),
          ),
        );

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;
        final String ref =
            RegExp(r'button "" \[ref=(e\d+)\]').firstMatch(snapshot)!.group(1)!;

        expect(RefRegistry.lookup(ref), isNotNull);
        expect(RefRegistry.lookupBinding(ref), isNull);
      });
    });
  });

  group('merged boundary tapOwner note (#60)', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets(
      'the issue tree names where the Skip intro control is, under its ref',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            mergedStageApp(onStageTap: () {}, onSkip: () {}),
          );

          final String snapshot =
              (await tapirSnapBuild())['snapshot'] as String;

          // The control is 120x40, inset 24px from the bottom-right corner.
          expect(
            snapshot,
            matches(
              RegExp(
                r'button "Skip intro" \[ref=e\d+\]\n\s+'
                r'tapOwner: \{"x":656\.0,"y":536\.0,"w":120\.0,"h":40\.0,'
                r'"centreHandled":true\}',
              ),
            ),
          );
        } finally {
          handle.dispose();
        }
      },
    );

    testWidgets('a plain button carries no tapOwner note', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: _button('Save'))),
        );

        final String snapshot = (await tapirSnapBuild())['snapshot'] as String;

        expect(snapshot, contains('"Save"'));
        expect(snapshot, isNot(contains('tapOwner')));
      } finally {
        handle.dispose();
      }
    });
  });
}
