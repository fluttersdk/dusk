import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_pointer.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// A `MergeSemantics` boundary absorbs the semantics of everything beneath it
/// into one platform node, yet the framework keeps each absorbed descendant as
/// its own `SemanticsNode` flagged `isMergedIntoParent`. Printing both told an
/// agent there were two controls where the platform exposes one.

/// Wind's `WSelect` and magic_starter's `MSSwitch` shape: the boundary owns the
/// tap, the inner container owns the label.
Widget _mergedButton({required VoidCallback onTap}) {
  return MaterialApp(
    home: Scaffold(
      body: MergeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Semantics(
            container: true,
            button: true,
            label: 'X',
            child: const Text('X'),
          ),
        ),
      ),
    ),
  );
}

/// A merged control whose absorbed node has an absorbed child of its own, so
/// the walk has to descend through one merged node into another.
Widget _deeplyMergedButton() {
  return MaterialApp(
    home: Scaffold(
      body: MergeSemantics(
        child: GestureDetector(
          onTap: () {},
          child: Semantics(
            container: true,
            button: true,
            label: 'X',
            child: Semantics(
              container: true,
              label: 'Y',
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Two real controls, one nested in the other, neither merged into a parent.
Widget _nestedButtons() {
  return MaterialApp(
    home: Scaffold(
      body: Semantics(
        container: true,
        button: true,
        label: 'Outer',
        child: Semantics(
          container: true,
          button: true,
          label: 'Inner',
          child: GestureDetector(
            onTap: () {},
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    ),
  );
}

/// Every semantics node of the live tree, merged ones included.
List<SemanticsNode> _rawNodes() {
  final List<SemanticsNode> nodes = <SemanticsNode>[];

  void collect(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren((SemanticsNode child) {
      collect(child);
      return true;
    });
  }

  void walkOwner(PipelineOwner owner) {
    final SemanticsNode? root = owner.semanticsOwner?.rootSemanticsNode;
    if (root != null) collect(root);
    owner.visitChildren(walkOwner);
  }

  walkOwner(RendererBinding.instance.rootPipelineOwner);
  return nodes;
}

List<String> _linesWith(String snapshot, String needle) {
  return snapshot
      .split('\n')
      .where((String line) => line.contains(needle))
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('duskSnapBuild merged semantics', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('a control merged into its parent is listed once', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_mergedButton(onTap: () {}));

        // The fixture only proves the case when the framework really did leave
        // a merged duplicate in the tree.
        expect(
          _rawNodes().where((SemanticsNode node) => node.isMergedIntoParent),
          isNotEmpty,
        );

        final String snapshot = (await duskSnapBuild())['snapshot'] as String;

        // The Text child adds its own `X` to the merged label, so the label is
        // matched by prefix rather than whole.
        expect(_linesWith(snapshot, '- button "X'), hasLength(1));
        expect(_linesWith(snapshot, '[ref='), hasLength(1));
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a merged node inside a merged node prints nothing', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_deeplyMergedButton());

        // Both `X` and `Y` are absorbed, so the walk descends through `X`
        // into `Y` before either is skipped.
        expect(
          _rawNodes().where((SemanticsNode node) => node.isMergedIntoParent),
          hasLength(greaterThanOrEqualTo(2)),
        );

        final String snapshot = (await duskSnapBuild())['snapshot'] as String;

        expect(_linesWith(snapshot, '[ref='), hasLength(1));
        expect(_linesWith(snapshot, '"Y"'), isEmpty);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a grep and a depth limit still see the boundary line', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_deeplyMergedButton());

        final String grepped =
            (await duskSnapBuild(grep: 'X', interactiveOnly: true))['snapshot']
                as String;
        expect(_linesWith(grepped, '[ref='), hasLength(1));

        RefRegistry.resetForTesting();
        final String shallow =
            (await duskSnapBuild(maxDepth: 1))['snapshot'] as String;
        expect(_linesWith(shallow, '"Y"'), isEmpty);
      } finally {
        handle.dispose();
      }
    });

    testWidgets('nested controls that are not merged are both listed', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_nestedButtons());

        expect(
          _rawNodes().where((SemanticsNode node) => node.isMergedIntoParent),
          isEmpty,
        );

        final String snapshot = (await duskSnapBuild())['snapshot'] as String;

        expect(_linesWith(snapshot, 'button "Outer"'), hasLength(1));
        expect(_linesWith(snapshot, 'button "Inner"'), hasLength(1));
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the surviving ref still taps the control', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        int taps = 0;
        await tester.pumpWidget(_mergedButton(onTap: () => taps += 1));

        final String snapshot = (await duskSnapBuild())['snapshot'] as String;
        final RegExpMatch? match =
            RegExp(r'\[ref=(\w+)\]').firstMatch(snapshot);
        expect(match, isNotNull);

        final Future<dynamic> pending =
            aiTestTapHandler('ext.dusk.tap', <String, String>{
          'ref': match!.group(1)!,
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          'includeSnapshot': 'false',
        });
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        await pending;

        expect(taps, 1);
      } finally {
        handle.dispose();
      }
    });
  });
}
