import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// Verifies the three ways a snapshot can be narrowed.
///
/// A full tree is the wrong default answer to most questions an agent asks.
/// It costs context, and on this app's shell it actively misleads: the
/// sidebar carries the same labels as the pages it opens, so an unscoped
/// lookup resolves the nav item and the agent concludes two pages differ.
Widget _shell() {
  return const MaterialApp(
    home: Scaffold(
      body: Row(
        children: <Widget>[
          _Region(
            label: 'sidebar',
            children: <Widget>[Text('Monitors'), Text('Settings')],
          ),
          _Region(
            label: 'content',
            children: <Widget>[
              Text('Monitors'),
              _Button(label: 'Create monitor'),
              Text('No monitors yet'),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Region extends StatelessWidget {
  const _Region({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // `header: true` gives the region a ref of its own, which is what a
    // caller passes to `within`. A label-only container carries no ref and
    // is therefore not addressable, which is the real constraint too.
    return Semantics(
      container: true,
      header: true,
      label: label,
      explicitChildNodes: true,
      child: SizedBox(width: 300, child: Column(children: children)),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: SizedBox(
          width: 200,
          height: 40,
          child: GestureDetector(
            onTap: () {},
            child: const SizedBox.expand(),
          )),
    );
  }
}

/// Resolves the ref of the first emitted node whose line carries [label].
String _refFor(String snapshot, String label) {
  for (final String line in snapshot.split('\n')) {
    if (!line.contains('"$label"')) continue;
    final RegExpMatch? match = RegExp(r'\[ref=(\w+)\]').firstMatch(line);
    if (match != null) return match.group(1)!;
  }
  throw StateError('no ref line for "$label" in:\n$snapshot');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('duskSnapBuild filters', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('interactiveOnly drops the plain text nodes', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      final Map<String, dynamic> payload =
          await duskSnapBuild(interactiveOnly: true);
      final String snapshot = payload['snapshot'] as String;

      expect(snapshot, contains('Create monitor'));
      expect(snapshot, isNot(contains('- text')));
      expect(snapshot, isNot(contains('No monitors yet')));
    });

    testWidgets('grep keeps matching nodes and the path to them', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      final Map<String, dynamic> payload = await duskSnapBuild(grep: 'Create');
      final String snapshot = payload['snapshot'] as String;

      expect(snapshot, contains('Create monitor'));
      // The enclosing region survives so its ref is still addressable.
      expect(snapshot, contains('content'));
      // Everything that neither matches nor leads to a match is gone.
      expect(snapshot, isNot(contains('No monitors yet')));
      expect(snapshot, isNot(contains('sidebar')));
    });

    testWidgets('within scopes the walk to one subtree', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      final String full = (await duskSnapBuild())['snapshot'] as String;
      final String contentRef = _refFor(full, 'content');

      final Map<String, dynamic> payload =
          await duskSnapBuild(within: contentRef);
      final String snapshot = payload['snapshot'] as String;

      // "Monitors" exists in BOTH regions. Unscoped, an exact-label lookup
      // resolves the sidebar's copy and the caller measures the wrong node.
      expect(snapshot, contains('Create monitor'));
      expect(snapshot, contains('No monitors yet'));
      expect(snapshot, isNot(contains('sidebar')));
    });

    testWidgets('within rejects a ref it cannot resolve', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      await expectLater(
        duskSnapBuild(within: 'e999'),
        throwsA(isA<StateError>()),
      );
    });

    testWidgets('an unfiltered snapshot is unchanged', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      final String snapshot = (await duskSnapBuild())['snapshot'] as String;

      expect(snapshot, contains('sidebar'));
      expect(snapshot, contains('No monitors yet'));
      expect(snapshot, contains('Create monitor'));
    });
  });
}
