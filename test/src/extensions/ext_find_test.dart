import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_find.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_pointer.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';
import 'package:fluttersdk_dusk/src/utils/dusk_exceptions.dart';
import 'package:fluttersdk_dusk/src/utils/error_envelope.dart';

/// Tests for the Playwright-Locator-style query handles introduced in
/// Step 16.
///
/// The contract:
///
/// 1. `extDuskFindHandler` mints a `q<N>` token when at least one
///    predicate (`text`, `semanticsLabel`, `key`) resolves to a live
///    Semantics + Element tree node.
/// 2. `qN` handles re-execute the stored predicates on every action call
///    (tap / hover / drag / type) — they survive widget rebuilds and
///    snapshot disposal.
/// 3. When the predicates no longer match anything live, action handlers
///    surface [DuskStaleHandleException] verbatim. They do NOT retry.
/// 4. `eN` snapshot refs continue to resolve via [RefRegistry.lookup] —
///    backward compat is non-negotiable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('extDuskFindHandler — predicate gating', () {
    setUp(RefRegistry.resetForTesting);

    test(
      '(a) zero predicates returns extensionError',
      () async {
        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{},
        );
        expect(response.result, isNull);
        expect(
          parseMessageFromErrorDetail(response.errorDetail ?? ''),
          contains(
              'at least one of "text", "contains", "semanticsLabel", or "key"'),
        );
      },
    );

    test(
      '(a) empty predicate values are treated as missing',
      () async {
        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'text': '', 'semanticsLabel': ''},
        );
        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          contains('at least one of'),
        );
      },
    );
  });

  group('extDuskFindHandler — match shape', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      '(b) text predicate returns a q-shape ref when match exists',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('Submit'))),
          ),
        );

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'text': 'Submit'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isTrue);
        expect(decoded['ref'], startsWith('q'));
      },
    );

    testWidgets(
      '(b) contains predicate matches Text.data via substring',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('You have pushed the button 5 times'),
              ),
            ),
          ),
        );

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'contains': 'pushed the button'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isTrue);
        expect(decoded['ref'], startsWith('q'));
      },
    );

    testWidgets(
      '(b) contains predicate matches SemanticsNode.label via substring',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  label: 'Sign in to your account now',
                  button: true,
                  container: true,
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'contains': 'Sign in'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isTrue);
        expect(decoded['ref'], startsWith('q'));
      },
    );

    testWidgets(
      '(b) contains predicate returns matched:false when no substring hits',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('Cancel'))),
          ),
        );

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'contains': 'pushed the button'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isFalse);
        expect(decoded['ref'], isNull);
      },
    );

    testWidgets(
      '(b) no match returns ref:null + matched:false (no q-token minted)',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('Cancel'))),
          ),
        );

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'text': 'Submit'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isFalse);
        expect(decoded['ref'], isNull);
      },
    );

    testWidgets(
      '(b) semanticsLabel predicate matches accessibility-only labels',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  label: 'AccessibleOnly',
                  button: true,
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'semanticsLabel': 'AccessibleOnly'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isTrue);
        expect(decoded['ref'], startsWith('q'));
      },
    );

    testWidgets(
      '(b) key predicate resolves a ValueKey via toString match',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                key: ValueKey<String>('monitor-row-7'),
                width: 200,
                height: 50,
              ),
            ),
          ),
        );

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'key': 'monitor-row-7'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isTrue);
        expect(decoded['ref'], startsWith('q'));
      },
    );
  });

  group('q-ref action re-resolution', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      '(c) q-ref tap re-resolves the query at action time',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: GestureDetector(
                  onTap: () => taps += 1,
                  child: Semantics(
                    label: 'tap-target',
                    button: true,
                    container: true,
                    child: Container(
                      width: 100,
                      height: 100,
                      color: const Color(0xFF000000),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final findResponse = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'semanticsLabel': 'tap-target'},
        );
        final String qRef = (jsonDecode(findResponse.result!)
            as Map<String, dynamic>)['ref'] as String;
        expect(qRef, startsWith('q'));

        // Opt out of the Step 3.1 stable + receives-events gates: the
        // q-ref rect is freshly resolved from the live semantics so
        // stable would normally pass, but the test scheduler does not
        // settle the gate's extra `await endOfFrame` deterministically.
        // Production callers leave the defaults.
        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': qRef,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.errorDetail, isNull);
        expect(response.result, isNotNull);
        expect(taps, equals(1));
      },
    );

    testWidgets(
      '(c) q-ref survives a widget rebuild that would invalidate an eN',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: GestureDetector(
                  onTap: () => taps += 1,
                  child: Semantics(
                    label: 'persistent-target',
                    button: true,
                    container: true,
                    child: Container(
                      width: 100,
                      height: 100,
                      color: const Color(0xFF111111),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final findResponse = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'semanticsLabel': 'persistent-target'},
        );
        final String qRef = (jsonDecode(findResponse.result!)
            as Map<String, dynamic>)['ref'] as String;

        // Rebuild the entire tree — the original SemanticsNode id changes
        // but the label stays put. An e-ref would now be stale; q-ref
        // should still resolve via the live tree walk.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('After rebuild')),
              body: Center(
                child: GestureDetector(
                  onTap: () => taps += 1,
                  child: Semantics(
                    label: 'persistent-target',
                    button: true,
                    container: true,
                    child: Container(
                      width: 100,
                      height: 100,
                      color: const Color(0xFF222222),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': qRef,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.errorDetail, isNull);
        expect(taps, equals(1));
      },
    );

    testWidgets(
      '(d) q-ref with no live match throws DuskStaleHandleException',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  label: 'will-vanish',
                  button: true,
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final findResponse = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'semanticsLabel': 'will-vanish'},
        );
        final String qRef = (jsonDecode(findResponse.result!)
            as Map<String, dynamic>)['ref'] as String;

        // Replace the entire tree with something the predicate does not
        // match. The stored DuskQuery now resolves to zero live nodes.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('something else'))),
          ),
        );

        final response = await aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{'ref': qRef},
        );

        expect(response.result, isNull);
        expect(
          response.errorDetail ?? '',
          contains('Query handle ref=$qRef is stale'),
        );

        // Sanity: the typed exception is the one we declared.
        expect(
          () => throw const DuskStaleHandleException(ref: 'q9'),
          throwsA(isA<DuskStaleHandleException>()),
        );
      },
    );
  });

  group('backward compat — e-shape refs', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      '(e) e-shape ref still resolves via RefRegistry.lookup (no regression)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('hello'))),
          ),
        );

        final Element element = tester.element(find.byType(Scaffold));
        final String eRef = RefRegistry.registerForTesting(
          rect: const Rect.fromLTWH(100, 100, 50, 50),
          element: element,
          groupId: 'g',
          isTextField: false,
        );
        expect(eRef, startsWith('e'));

        final future = aiTestTapHandler(
          'ext.dusk.tap',
          <String, String>{
            'ref': eRef,
            'checkStable': 'false',
            'checkReceivesEvents': 'false',
          },
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.errorDetail, isNull);
        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['ref'], equals(eRef));
      },
    );
  });

  group('multi-match semanticsLabel diagnostic', () {
    setUp(RefRegistry.resetForTesting);

    testWidgets(
      '(f) two nodes sharing a semanticsLabel produce a multi-match diagnostic',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Two distinct semantics nodes with the same label — models the
        // "Password" over-match scenario from REPORT #15.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Semantics(
                    label: 'Password',
                    textField: true,
                    container: true,
                    child: const SizedBox(width: 200, height: 50),
                  ),
                  Semantics(
                    label: 'Password',
                    textField: true,
                    container: true,
                    child: const SizedBox(width: 200, height: 50),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'semanticsLabel': 'Password'},
        );

        // Still resolves (backward-compatible); a q-handle is minted.
        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isTrue);
        expect(decoded['ref'], startsWith('q'));

        // Multi-match diagnostic is present.
        expect(decoded['matchCount'], equals(2));
        expect(
          decoded['diagnostic'] as String? ?? '',
          contains("label 'Password' matched 2 nodes"),
        );
      },
    );

    testWidgets(
      '(f) single-match semanticsLabel carries no multi-match diagnostic',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Semantics(
                  label: 'UniqueLabel',
                  button: true,
                  container: true,
                  child: const SizedBox(width: 100, height: 100),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final response = await extDuskFindHandler(
          'ext.dusk.find',
          <String, String>{'semanticsLabel': 'UniqueLabel'},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['matched'], isTrue);
        expect(decoded['matchCount'], equals(1));
        // No diagnostic key present on single match.
        expect(decoded.containsKey('diagnostic'), isFalse);
      },
    );
  });

  group('RefRegistry query store', () {
    setUp(RefRegistry.resetForTesting);

    test('registerQuery mints q-shape tokens; lookupQuery round-trips', () {
      final String first = RefRegistry.registerQuery(
        const DuskQuery(text: 'Submit'),
      );
      final String second = RefRegistry.registerQuery(
        const DuskQuery(semanticsLabel: 'Cancel'),
      );

      expect(first, equals('q1'));
      expect(second, equals('q2'));

      expect(RefRegistry.lookupQuery(first)?.text, equals('Submit'));
      expect(
        RefRegistry.lookupQuery(second)?.semanticsLabel,
        equals('Cancel'),
      );

      // e-shape lookup never hits the queries map.
      expect(RefRegistry.lookupQuery('e1'), isNull);
      // Unknown q-token returns null.
      expect(RefRegistry.lookupQuery('q99'), isNull);
    });

    test('resetForTesting clears both q and e tokens', () {
      RefRegistry.registerQuery(const DuskQuery(text: 'a'));
      RefRegistry.resetForTesting();
      expect(RefRegistry.lookupQuery('q1'), isNull);
      // Counter resets — next mint is q1 again.
      final String next = RefRegistry.registerQuery(const DuskQuery(text: 'b'));
      expect(next, equals('q1'));
    });
  });
}
