import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_find.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_observe.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_pointer.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// A `MergeSemantics` boundary absorbs the semantics of everything beneath it
/// into one platform node, yet the framework keeps each absorbed descendant as
/// its own `SemanticsNode` flagged `isMergedIntoParent`. Observe listed both,
/// which told an agent there were two controls where the platform exposes one.

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

/// A merged node that shares its OWN label with a later, unmerged button. The
/// resolver counts the merged one, so the later button's index has to as well.
Widget _mergedNodeSharingALabel() {
  return MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          MergeSemantics(
            child: GestureDetector(
              onTap: () {},
              child: Semantics(
                container: true,
                button: true,
                label: 'Favourite',
                child: const SizedBox(width: 100, height: 40),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              container: true,
              button: true,
              label: 'Favourite',
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Every semantics node of the live tree, merged ones included, in the
/// pre-order the find resolver counts them in.
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

Future<List<Map<String, dynamic>>> _observe() async {
  final response = await extDuskObserveHandler(
    'ext.dusk.observe',
    <String, String>{},
  );
  final Map<String, dynamic> body =
      jsonDecode(response.result!) as Map<String, dynamic>;

  return <Map<String, dynamic>>[
    for (final dynamic entry in body['candidates'] as List<dynamic>)
      entry as Map<String, dynamic>,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('extDuskObserveHandler merged semantics', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

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

        final List<Map<String, dynamic>> candidates = await _observe();

        expect(candidates, hasLength(1));
        expect(candidates.single['role'], 'button');
      } finally {
        handle.dispose();
      }
    });

    testWidgets('a merged node inside a merged node yields no candidate', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(_deeplyMergedButton());

        expect(
          _rawNodes().where((SemanticsNode node) => node.isMergedIntoParent),
          hasLength(greaterThanOrEqualTo(2)),
        );

        expect(await _observe(), hasLength(1));
      } finally {
        handle.dispose();
      }
    });

    testWidgets('the surviving q ref re-resolves and taps the control', (
      WidgetTester tester,
    ) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      try {
        int taps = 0;
        await tester.pumpWidget(_mergedButton(onTap: () => taps += 1));

        final List<Map<String, dynamic>> candidates = await _observe();
        expect(candidates, hasLength(1));

        final String ref = candidates.single['ref'] as String;
        expect(ref, startsWith('q'));
        expect(resolveQuery(RefRegistry.lookupQuery(ref)!), isNotNull);

        final Future<dynamic> pending =
            aiTestTapHandler('ext.dusk.tap', <String, String>{
          'ref': ref,
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

        final List<Map<String, dynamic>> candidates = await _observe();

        expect(
          candidates.map((Map<String, dynamic> c) => c['label']),
          containsAll(<String>['Outer', 'Inner']),
        );
        expect(candidates, hasLength(2));
      } finally {
        handle.dispose();
      }
    });

    testWidgets(
      'a merged node sharing its label does not shift a later node index',
      (WidgetTester tester) async {
        final SemanticsHandle handle = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_mergedNodeSharingALabel());

          final List<SemanticsNode> raw = _rawNodes();
          final List<SemanticsNode> favourites = raw
              .where((SemanticsNode node) => node.label == 'Favourite')
              .toList();

          // The later node is the last one carrying the label and is not
          // merged; the merged one has to sit ahead of it for the case to mean
          // anything.
          final SemanticsNode later = favourites.last;
          expect(later.isMergedIntoParent, isFalse);
          expect(
            favourites.any((SemanticsNode node) => node.isMergedIntoParent),
            isTrue,
          );

          // The resolver counts every node whose own label matches, in
          // pre-order, so its index for the later node is how many came first.
          final int expectedIndex = favourites.indexOf(later);
          expect(expectedIndex, greaterThan(0));

          final List<Map<String, dynamic>> candidates = await _observe();
          final Map<String, dynamic> laterCandidate = candidates.last;

          final DuskQuery query = RefRegistry.lookupQuery(
            laterCandidate['ref'] as String,
          )!;
          expect(query.matchIndex, expectedIndex);

          final double top =
              (laterCandidate['bounds'] as Map<String, dynamic>)['y'] as double;
          expect(resolveQuery(query)!.rect.top, top);
        } finally {
          handle.dispose();
        }
      },
    );
  });
}
