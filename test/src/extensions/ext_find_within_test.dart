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

/// Same two regions, with a keyed row and a distinctive substring parked in
/// the sidebar only, so a scope that fails to bind still finds them.
Widget _keyedShell() {
  return const MaterialApp(
    home: Scaffold(
      body: Row(
        children: <Widget>[
          _Region(
            label: 'sidebar',
            child: Column(
              children: <Widget>[
                SizedBox(key: Key('sidebar-row'), width: 10, height: 10),
                Text('Sidebar copy here'),
              ],
            ),
          ),
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

    testWidgets('a scope with no semantics node does not widen to the tree', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_shell());

      // `find_by_text` mints an element-only entry (ext_wait_find.dart:433
      // registers without a `node`), so a ref taken from a `dusk:wait`
      // result arrives here carrying no semantics node. The scope still has
      // to hold: falling back to a whole-tree semantics walk would answer a
      // different question than the caller asked, and answer it plausibly.
      final Element scope = tester.element(find.byType(Scaffold));
      final String ref = RefRegistry.register(
        rect: const Rect.fromLTWH(0, 0, 300, 40),
        element: scope,
        groupId: 'element-only',
        isTextField: false,
      );

      final developer.ServiceExtensionResponse response =
          await extDuskFindHandler(
        'ext.dusk.find',
        <String, String>{'semanticsLabel': 'Monitors', 'within': ref},
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['matched'], isFalse);
      expect(decoded['diagnostic'], contains('no semantics node'));
    });

    testWidgets('a text scope with no semantics node still searches elements', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: <Widget>[
                SizedBox(width: 300, child: Text('Monitors')),
                SizedBox(width: 300, child: Text('Uptime')),
              ],
            ),
          ),
        ),
      );

      // The semantics leg is unusable without a scope node, but the element
      // leg is scoped by the entry's element, so a text lookup still has a
      // correct answer to give rather than a refusal.
      final Element scope = tester.element(find.text('Uptime').first);
      final String ref = RefRegistry.register(
        rect: const Rect.fromLTWH(0, 0, 300, 40),
        element: scope,
        groupId: 'element-only',
        isTextField: false,
      );

      final developer.ServiceExtensionResponse hit = await extDuskFindHandler(
        'ext.dusk.find',
        <String, String>{'text': 'Uptime', 'within': ref},
      );
      expect(
        (jsonDecode(hit.result!) as Map<String, dynamic>)['matched'],
        isTrue,
      );

      final developer.ServiceExtensionResponse miss = await extDuskFindHandler(
        'ext.dusk.find',
        <String, String>{'text': 'Monitors', 'within': ref},
      );
      expect(
        (jsonDecode(miss.result!) as Map<String, dynamic>)['matched'],
        isFalse,
        reason: 'Monitors sits outside the scoped element subtree',
      );
    });

    testWidgets('within bounds a key lookup', (WidgetTester tester) async {
      await tester.pumpWidget(_keyedShell());

      final String snapshot = (await duskSnapBuild())['snapshot'] as String;
      final String contentRef = _refFor(snapshot, 'content');

      final developer.ServiceExtensionResponse response =
          await extDuskFindHandler(
        'ext.dusk.find',
        <String, String>{'key': 'sidebar-row', 'within': contentRef},
      );

      expect(
        (jsonDecode(response.result!) as Map<String, dynamic>)['matched'],
        isFalse,
        reason: 'the key lives in the sidebar, outside the named scope',
      );
    });

    testWidgets('within bounds a contains lookup', (WidgetTester tester) async {
      await tester.pumpWidget(_keyedShell());

      final String snapshot = (await duskSnapBuild())['snapshot'] as String;
      final String contentRef = _refFor(snapshot, 'content');

      final developer.ServiceExtensionResponse response =
          await extDuskFindHandler(
        'ext.dusk.find',
        <String, String>{'contains': 'Sidebar copy', 'within': contentRef},
      );

      expect(
        (jsonDecode(response.result!) as Map<String, dynamic>)['matched'],
        isFalse,
        reason: 'the substring only appears in the sidebar',
      );
    });
  });

  group('a scope ref that no longer lives is refused, not walked', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    /// Mints a scope ref against one screen, then replaces the screen. The
    /// registry keeps the token: nothing calls `disposeGroup` in production,
    /// so the entry outlives the widget it was minted from.
    Future<String> refFromReplacedScreen(WidgetTester tester) async {
      await tester.pumpWidget(_shell());
      final String snapshot = (await duskSnapBuild())['snapshot'] as String;
      final String ref = _refFor(snapshot, 'content');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('a different screen'))),
        ),
      );
      return ref;
    }

    testWidgets('snap refuses rather than returning the old screen', (
      WidgetTester tester,
    ) async {
      // The quiet one. A detached SemanticsNode still answers visitChildren,
      // so the walk succeeded against a subtree that is no longer on screen
      // and the caller got a snapshot of the PREVIOUS page with no error to
      // say so.
      final String ref = await refFromReplacedScreen(tester);

      final developer.ServiceExtensionResponse response = await duskSnapHandler(
        'ext.dusk.snap',
        <String, String>{'within': ref},
      );

      expect(
        response.result,
        isNull,
        reason: 'returned a snapshot of the replaced screen',
      );
      expect(response.errorDetail, contains('no longer'));
    });

    testWidgets('find reports the scope is gone instead of throwing', (
      WidgetTester tester,
    ) async {
      // The loud one, but wrongly worded: the guard only checked registry
      // membership, so a stale entry passed it and the walk then called
      // visitChildElements on a defunct element, surfacing as a generic
      // `unexpected` envelope rather than the re-snapshot diagnostic that
      // tells the agent what to do next.
      final String ref = await refFromReplacedScreen(tester);

      final developer.ServiceExtensionResponse response =
          await extDuskFindHandler(
        'ext.dusk.find',
        <String, String>{'semanticsLabel': 'Monitors', 'within': ref},
      );

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['matched'], isFalse);
      expect(decoded['diagnostic'], contains('no longer'));
    });
  });
}
