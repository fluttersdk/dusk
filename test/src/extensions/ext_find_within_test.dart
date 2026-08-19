import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_find.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// Verifies that `find` can be scoped to a subtree.
///
/// A shell whose sidebar repeats the labels of the pages it opens makes an
/// unscoped exact-label lookup resolve the nav item, and the caller then
/// measures the sidebar and concludes two pages differ. Scoping is the fix,
/// and it has to survive into the `q<N>` handle: a scoped locator that
/// forgets its scope on the next re-resolve is worse than none.
Widget _shell() {
  return const MaterialApp(
    home: Scaffold(
      body: Row(
        children: <Widget>[
          _Region(label: 'sidebar', child: _Button(label: 'Monitors')),
          _Region(label: 'content', child: _Button(label: 'Monitors')),
        ],
      ),
    ),
  );
}

class _Region extends StatelessWidget {
  const _Region({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      header: true,
      label: label,
      explicitChildNodes: true,
      child: SizedBox(width: 300, child: child),
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
        child: GestureDetector(onTap: () {}, child: const SizedBox.expand()),
      ),
    );
  }
}

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

  group('ext.dusk.find within', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('an unscoped match is ambiguous across the shell', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      final developer.ServiceExtensionResponse response =
          await extDuskFindHandler(
        'ext.dusk.find',
        const <String, String>{'semanticsLabel': 'Monitors'},
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['matched'], isTrue);
      expect(decoded['matchCount'], equals(2));
      expect(decoded['diagnostic'], contains('matched 2 nodes'));
    });

    testWidgets('within narrows the match to one region', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      final String snapshot = (await duskSnapBuild())['snapshot'] as String;
      final String contentRef = _refFor(snapshot, 'content');

      final developer.ServiceExtensionResponse response =
          await extDuskFindHandler(
        'ext.dusk.find',
        <String, String>{'semanticsLabel': 'Monitors', 'within': contentRef},
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['matched'], isTrue);
      expect(
        decoded['matchCount'],
        equals(1),
        reason: 'the sidebar copy is outside the scope',
      );
      expect(decoded.containsKey('diagnostic'), isFalse);
    });

    testWidgets('a scope that no longer resolves reports no match', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      final developer.ServiceExtensionResponse response =
          await extDuskFindHandler(
        'ext.dusk.find',
        const <String, String>{'semanticsLabel': 'Monitors', 'within': 'e999'},
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['matched'], isFalse);
      expect(decoded['diagnostic'], contains('e999'));
    });
  });
}
