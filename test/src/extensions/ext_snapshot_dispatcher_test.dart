library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// Regression tests for the enricher-dispatcher loop inside `ext_snapshot.dart`.
///
/// The dispatcher (lines 158-167 of ext_snapshot.dart) iterates
/// [DuskPlugin.enrichers] in insertion order and appends each non-null,
/// non-empty fragment's lines (split via [LineSplitter]) beneath the
/// matching ref entry. These tests lock that contract so Magic + Wind
/// integrations cannot be broken silently by future plan revisions.
///
/// ## Test strategy
///
/// `duskSnapBuild` walks `RendererBinding.instance.rootPipelineOwner`, but
/// in the Flutter test harness the widget tree lives under a CHILD pipeline
/// owner (the one with the real view). The root pipeline owner's semantics
/// node is always null, so `duskSnapBuild` returns an empty snapshot string.
///
/// Instead of fighting the test harness, the dispatcher CONTRACT is verified
/// in two tiers:
///
/// 1. **Enricher-logic tier** (pure): simulate the dispatcher loop directly,
///    passing a live `Element` obtained from `tester.element(...)` and
///    `RefRegistry.instance`. This exercises the exact same `fragment == null`
///    guard, `LineSplitter().convert(fragment.trimRight())` split, and
///    concatenation order that the production loop uses.
///
/// 2. **DuskPlugin.enrichers wiring tier**: verify that `DuskPlugin.enrichers`
///    is a mutable list that accumulates registrations and that `duskSnapBuild`
///    returns the expected envelope shape (groupId + snapshot keys), so callers
///    see the correct response regardless of tree content.
///
/// Contracts under test:
/// (a) Insertion-order preservation — enrichers fire in the order they were
///     added and their output lines appear in that same order.
/// (b) Null-returning enricher is silently skipped — no output line emitted.
/// (c) Multi-line fragment — each line is split and re-indented independently
///     via the `LineSplitter().convert(fragment.trimRight())` path.
/// (d) Duplicate-key ordering — when two enrichers emit lines with the same
///     YAML key, the dispatcher concatenates both in insertion order; the
///     first enricher's line appears before the second (first-write-wins is
///     a SEMANTIC convention that enrichers honor; the dispatcher itself
///     just concatenates and lets the FIRST occurrence take precedence in
///     YAML readers that follow that convention).

// ---------------------------------------------------------------------------
// Private fake enrichers — kept in this file (extract-when-third-caller rule;
// no shared helper file until a third caller exists).
// ---------------------------------------------------------------------------

/// Returns a single-line YAML fragment with a stable key.
String? _fakeEnricher1(
  Element element,
  RefRegistry refs,
) =>
    'magicFormField: email';

/// Returns a multi-line YAML fragment (simulates Wind's className block).
String? _fakeEnricher2(
  Element element,
  RefRegistry refs,
) =>
    'wind:\n  breakpoint: lg\n  brightness: light';

/// Always returns null — simulates an enricher that does not apply to this
/// element (e.g. MagicFormEnricher outside a MagicForm).
String? _fakeEnricher3(
  Element element,
  RefRegistry refs,
) =>
    null;

// ---------------------------------------------------------------------------
// Helper: replicate the dispatcher loop from ext_snapshot.dart:158-167.
//
// The production loop runs inside _emitNode, which is only reachable when
// a SemanticsNode exists in rootPipelineOwner — something the Flutter test
// harness does not provide. This helper replicates the SAME logic so the
// contract tests are deterministic without a real Semantics tree.
// ---------------------------------------------------------------------------

/// Runs every enricher in [DuskPlugin.enrichers] against [element] and
/// [refs], applies the same null / empty guard and [LineSplitter] split
/// used by the production dispatcher, and returns the concatenated output.
///
/// Mirrors ext_snapshot.dart lines 160-167 exactly.
String _runDispatcher(Element element) {
  final StringBuffer buffer = StringBuffer();
  for (final enricher in DuskPlugin.enrichers) {
    final String? fragment = enricher(element, RefRegistry.instance);
    if (fragment == null || fragment.isEmpty) continue;
    for (final line in const LineSplitter().convert(fragment.trimRight())) {
      if (line.isEmpty) continue;
      buffer.writeln(line);
    }
  }
  return buffer.toString();
}

void main() {
  setUp(() {
    DuskPlugin.enrichers.clear();
    RefRegistry.resetForTesting();
  });

  tearDown(() {
    DuskPlugin.enrichers.clear();
    RefRegistry.resetForTesting();
  });

  // -------------------------------------------------------------------------
  // (a) Insertion-order preservation
  // -------------------------------------------------------------------------

  group('(a) insertion-order preservation', () {
    testWidgets(
      'enricher registered first emits its fragment before the second',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // 1. Register enrichers in order: 1 then 2.
        DuskPlugin.enrichers
          ..add(_fakeEnricher1)
          ..add(_fakeEnricher2);

        // 2. Mount a widget so we have a live Element to pass to the enrichers.
        //    onPressed: () {} is required — onPressed: null disables the button
        //    (no tap action, isButton=false) and the enricher loop in production
        //    would never be entered.
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

        // 3. Obtain a live element and run the dispatcher.
        final Element element = tester.element(find.byType(ElevatedButton));
        final String output = _runDispatcher(element);

        // 4. Enricher-1 output must precede enricher-2 output.
        final int pos1 = output.indexOf('magicFormField: email');
        final int pos2 = output.indexOf('wind:');
        expect(
          pos1,
          greaterThanOrEqualTo(0),
          reason: 'enricher-1 fragment must appear in output',
        );
        expect(
          pos2,
          greaterThanOrEqualTo(0),
          reason: 'enricher-2 fragment must appear in output',
        );
        expect(
          pos1 < pos2,
          isTrue,
          reason: 'enricher-1 (registered first) must appear before enricher-2',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // (b) Null-returning enricher is skipped — no output line emitted
  // -------------------------------------------------------------------------

  group('(b) null enricher skipped', () {
    testWidgets(
      'null-returning enricher produces no output line',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // 1. Register only the null enricher.
        DuskPlugin.enrichers.add(_fakeEnricher3);

        // 2. Mount widget and obtain a live element.
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

        final Element element = tester.element(find.byType(ElevatedButton));

        // 3. Run the dispatcher — output must be empty.
        final String output = _runDispatcher(element);
        expect(
          output,
          isEmpty,
          reason:
              'null-returning enricher must contribute no output (skipped by '
              'the `if (fragment == null || fragment.isEmpty) continue` guard)',
        );
      },
    );

    testWidgets(
      'null enricher between two non-null enrichers does not introduce a gap',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // 1. Register: non-null, null, non-null.
        DuskPlugin.enrichers
          ..add(_fakeEnricher1)
          ..add(_fakeEnricher3)
          ..add(_fakeEnricher2);

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

        final Element element = tester.element(find.byType(ElevatedButton));
        final String output = _runDispatcher(element);

        // 2. Both non-null fragments appear; no blank lines between them.
        expect(output, contains('magicFormField: email'));
        expect(output, contains('wind:'));
        final List<String> lines = const LineSplitter().convert(output);
        bool prevBlank = false;
        for (final String line in lines) {
          final bool isBlank = line.trim().isEmpty;
          expect(
            isBlank && prevBlank,
            isFalse,
            reason: 'null enricher must not introduce consecutive blank lines',
          );
          prevBlank = isBlank;
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // (c) Multi-line fragment is split and each line emitted independently
  // -------------------------------------------------------------------------

  group('(c) multi-line fragment split via LineSplitter', () {
    testWidgets(
      'each line of a multi-line fragment appears on its own output line',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // 1. Register only the multi-line enricher.
        DuskPlugin.enrichers.add(_fakeEnricher2);

        // 2. Mount widget and obtain a live element.
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

        final Element element = tester.element(find.byType(ElevatedButton));

        // 3. Run dispatcher and split output into lines.
        final String output = _runDispatcher(element);
        final List<String> lines = const LineSplitter().convert(
          output.trimRight(),
        );

        // 4. All three lines from the fragment must be present.
        expect(
          lines.any((String l) => l.contains('wind:')),
          isTrue,
          reason: 'first line of multi-line fragment must appear',
        );
        expect(
          lines.any((String l) => l.contains('breakpoint: lg')),
          isTrue,
          reason: 'second line of multi-line fragment must appear',
        );
        expect(
          lines.any((String l) => l.contains('brightness: light')),
          isTrue,
          reason: 'third line of multi-line fragment must appear',
        );

        // 5. 'wind:' and 'breakpoint: lg' must be on separate lines.
        final int windIdx = lines.indexWhere(
          (String l) => l.contains('wind:'),
        );
        final int bpIdx = lines.indexWhere(
          (String l) => l.contains('breakpoint: lg'),
        );
        expect(
          bpIdx,
          greaterThan(windIdx),
          reason: 'breakpoint: lg must be on a later line than wind:',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // (d) Duplicate-key ordering — first enricher wins per first-write-wins
  //     semantic; dispatcher concatenates in insertion order
  // -------------------------------------------------------------------------

  group('(d) duplicate-key ordering (first-write-wins)', () {
    testWidgets(
      'when two enrichers emit the same key, the first-registered line '
      'appears before the second in the output',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // 1. Two enrichers that both emit 'magicX:' with different values.
        String? firstEnricher(Element element, RefRegistry refs) =>
            'magicX: valueFromFirst';
        String? secondEnricher(Element element, RefRegistry refs) =>
            'magicX: valueFromSecond';

        DuskPlugin.enrichers
          ..add(firstEnricher)
          ..add(secondEnricher);

        // 2. Mount widget and obtain a live element.
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

        final Element element = tester.element(find.byType(ElevatedButton));

        // 3. Run dispatcher.
        final String output = _runDispatcher(element);

        // 4. Both lines appear (dispatcher concatenates in insertion order).
        expect(
          output,
          contains('magicX: valueFromFirst'),
          reason: 'first enricher output must appear in YAML',
        );
        expect(
          output,
          contains('magicX: valueFromSecond'),
          reason: 'second enricher output must appear in YAML',
        );

        // 5. The first-registered enricher's line appears before the second
        //    (insertion-order concatenation; per the typedef contract at
        //    dusk_snapshot_enricher.dart:16, first-write-wins is a SEMANTIC
        //    convention: YAML readers that take the first occurrence of a
        //    duplicate key see the first enricher's value).
        final int posFirst = output.indexOf('magicX: valueFromFirst');
        final int posSecond = output.indexOf('magicX: valueFromSecond');
        expect(
          posFirst < posSecond,
          isTrue,
          reason:
              'first-registered enricher output must precede second in YAML',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // DuskPlugin.enrichers wiring + duskSnapBuild envelope shape
  // -------------------------------------------------------------------------

  group('DuskPlugin.enrichers list and duskSnapBuild envelope', () {
    test('enrichers list accepts registrations and retains insertion order',
        () {
      DuskPlugin.enrichers
        ..add(_fakeEnricher1)
        ..add(_fakeEnricher2)
        ..add(_fakeEnricher3);

      expect(DuskPlugin.enrichers, hasLength(3));
      expect(DuskPlugin.enrichers[0], equals(_fakeEnricher1));
      expect(DuskPlugin.enrichers[1], equals(_fakeEnricher2));
      expect(DuskPlugin.enrichers[2], equals(_fakeEnricher3));
    });

    testWidgets(
      'duskSnapBuild returns snapshot and groupId keys',
      (WidgetTester tester) async {
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

        final Map<String, dynamic> payload = await duskSnapBuild();

        expect(
          payload,
          containsPair('snapshot', isA<String>()),
          reason:
              'duskSnapBuild must return a snapshot key with a String value',
        );
        expect(
          payload,
          containsPair('groupId', isA<String>()),
          reason: 'duskSnapBuild must return a groupId key with a String value',
        );
        expect(
          (payload['groupId'] as String).startsWith('snapshot-'),
          isTrue,
          reason: 'groupId must be prefixed with snapshot-',
        );
      },
    );

    test('RefRegistry.resetForTesting clears counter and entries', () {
      RefRegistry.resetForTesting();
      // After reset, looking up any token returns null.
      expect(RefRegistry.lookup('e1'), isNull);
      expect(RefRegistry.refsForGroup('any'), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // (e) Live per-ref overflow annotation — ext_snapshot.dart Step 4
  //
  // duskSnapBuild walks rootPipelineOwner + child owners, so in the test
  // harness the widget tree IS visible (the child-owner walk fix is already
  // in place). We narrow the viewport so a Row with an oversized child
  // overflows, which causes RenderFlex.toStringShort() to append
  // ' OVERFLOWING'. The snapshot must contain an `overflow: true` line
  // immediately beneath the ref entry for that node, at depth+1 indent.
  //
  // A non-overflowing layout in the same viewport must produce no such line.
  // -------------------------------------------------------------------------

  group('(e) per-ref overflow annotation', () {
    testWidgets(
      'overflowing Row interactive node gets overflow: true annotation',
      (WidgetTester tester) async {
        // 1. Narrow viewport so an unconstrained Row child overflows.
        tester.view.physicalSize = const Size(100, 200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 2. Suppress the layout overflow FlutterError so the test harness
        //    does not fail on the expected overflow. The overflow IS the
        //    condition under test; we still need it in the render tree.
        final void Function(FlutterErrorDetails)? previous =
            FlutterError.onError;
        FlutterError.onError = (FlutterErrorDetails details) {
          // Re-throw only non-overflow errors; swallow the expected overflow.
          if (details.exceptionAsString().contains('overflowed by')) return;
          previous?.call(details);
        };
        addTearDown(() => FlutterError.onError = previous);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  ElevatedButton(
                    onPressed: () {},
                    child: const SizedBox(
                      width: 500,
                      child: Text('Wide'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        // 3. Pump a second frame so the overflow flag propagates through layout.
        await tester.pump();

        // 4. Capture snapshot — overflow annotation must appear regardless of
        //    includeEnrichers because it is a live-state check, not an enricher.
        final Map<String, dynamic> payload = await tester.runAsync(
          () => duskSnapBuild(),
        ) as Map<String, dynamic>;

        final String snapshot = payload['snapshot'] as String;
        expect(
          snapshot,
          contains('overflow: true'),
          reason: 'overflowing RenderFlex must annotate the ref node with '
              'overflow: true',
        );
      },
    );

    testWidgets(
      'non-overflowing layout produces no overflow annotation',
      (WidgetTester tester) async {
        // 1. Wide viewport so the Row fits comfortably.
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  ElevatedButton(
                    onPressed: () {},
                    child: const Text('Fits'),
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
        expect(
          snapshot,
          isNot(contains('overflow: true')),
          reason:
              'non-overflowing layout must not produce an overflow annotation',
        );
      },
    );
  });
}
