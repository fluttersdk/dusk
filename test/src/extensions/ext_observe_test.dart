import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_find.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_observe.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';
import 'package:fluttersdk_wind_diagnostics_contracts/fluttersdk_wind_diagnostics_contracts.dart';

/// Fake resolver that emits the 6 core wind fields for any Element.
/// Used to assert the new `WindDebugRegistry` walk in `_mergeEnricherFields`
/// (wind alpha-10 replaces the enricher-list contribution).
class _FakeWindResolver implements WindDebugResolver {
  @override
  Map<String, Object?> resolve(Element element) {
    return const <String, Object?>{
      'className': 'flex p-4',
      'breakpoint': 'lg',
      'brightness': 'dark',
      'platform': 'web',
      'states': <String>['hover'],
      'bgColor': '#3B82F6',
    };
  }
}

/// Tests for `ext.dusk.observe` (Stagehand observe-once-act-many).
///
/// Contract:
///
/// 1. Returns `{candidates: [...], count: N}` with one entry per interactive
///    Semantics + Element-tree node.
/// 2. Every candidate has a `ref` minted via [RefRegistry.registerQuery] so the
///    ref re-resolves to the live tree on each follow-up action (Playwright
///    Locator pattern). The ref is ALWAYS q-shape, never e-shape.
/// 3. Each candidate carries: `role`, `label`, `value`, `bounds` (x/y/w/h),
///    `isEnabled`, `isVisible`.
/// 4. `roles` param (csv) filters down to the listed roles.
/// 5. `limit` param caps the candidate list length (default 50).
/// 6. `includeEnrichers` param toggles per-candidate enricher fields:
///    - `'false'` -> no enricher fields,
///    - `'true'` (default) -> default subset `{magicFormField, magicRoute,
///      magicGateResult, wind (breakpoint + states only)}`,
///    - `'full'` -> every enricher field (incl. all wind sub-fields).
/// 7. NO server-side LLM is invoked. `intent` is accepted as a caller hint and
///    echoed back optionally; the agent decides which refs to act on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('extDuskObserveHandler — basic candidate enumeration', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    testWidgets(
      '(a) returns one candidate per interactive node in a mixed tree',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  ElevatedButton(onPressed: () {}, child: const Text('B1')),
                  ElevatedButton(onPressed: () {}, child: const Text('B2')),
                  ElevatedButton(onPressed: () {}, child: const Text('B3')),
                  ElevatedButton(onPressed: () {}, child: const Text('B4')),
                  ElevatedButton(onPressed: () {}, child: const Text('B5')),
                  const TextField(),
                  const TextField(),
                  const TextField(),
                  Checkbox(value: false, onChanged: (_) {}),
                  Checkbox(value: true, onChanged: (_) {}),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> candidates = decoded['candidates'] as List<dynamic>;

        // 5 buttons + 3 textfields + 2 checkboxes = 10.
        expect(decoded['count'], equals(candidates.length));
        expect(candidates.length, equals(10));
      },
    );

    testWidgets(
      '(b) every candidate carries a q-shape ref (never e-shape)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> candidates = decoded['candidates'] as List<dynamic>;

        expect(candidates, isNotEmpty);
        for (final dynamic entry in candidates) {
          final String ref = (entry as Map<String, dynamic>)['ref'] as String;
          expect(
            ref.startsWith('q'),
            isTrue,
            reason: 'observe must mint q-shape refs only; got "$ref"',
          );
        }
      },
    );

    testWidgets(
      '(c) every candidate carries role / label / bounds / isEnabled / isVisible',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

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
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> candidates = decoded['candidates'] as List<dynamic>;
        final Map<String, dynamic> first =
            candidates.first as Map<String, dynamic>;

        expect(first['role'], equals('button'));
        expect(first['label'], equals('Submit'));
        expect(first['isEnabled'], isTrue);
        expect(first['isVisible'], isTrue);

        final Map<String, dynamic> bounds =
            first['bounds'] as Map<String, dynamic>;
        expect(bounds['x'], isA<num>());
        expect(bounds['y'], isA<num>());
        expect(bounds['w'], greaterThan(0));
        expect(bounds['h'], greaterThan(0));
      },
    );
  });

  group('extDuskObserveHandler — roles filter', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    testWidgets(
      '(d) roles=button returns only button candidates',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  ElevatedButton(onPressed: () {}, child: const Text('B1')),
                  ElevatedButton(onPressed: () {}, child: const Text('B2')),
                  ElevatedButton(onPressed: () {}, child: const Text('B3')),
                  ElevatedButton(onPressed: () {}, child: const Text('B4')),
                  ElevatedButton(onPressed: () {}, child: const Text('B5')),
                  const TextField(),
                  const TextField(),
                  const TextField(),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{'roles': 'button'},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> candidates = decoded['candidates'] as List<dynamic>;

        expect(candidates, hasLength(5));
        for (final dynamic entry in candidates) {
          expect(
            (entry as Map<String, dynamic>)['role'],
            equals('button'),
          );
        }
      },
    );

    testWidgets(
      '(e) roles=button,textbox accepts a CSV list',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  ElevatedButton(onPressed: () {}, child: const Text('B1')),
                  const TextField(),
                  Checkbox(value: false, onChanged: (_) {}),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{'roles': 'button,textbox'},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> candidates = decoded['candidates'] as List<dynamic>;

        final Set<String> roles = candidates
            .map<String>(
                (dynamic e) => (e as Map<String, dynamic>)['role'] as String)
            .toSet();
        expect(roles, containsAll(<String>['button', 'textbox']));
        expect(roles.contains('checkbox'), isFalse);
      },
    );
  });

  group('extDuskObserveHandler — limit param', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    testWidgets(
      '(f) limit=3 caps the list at 3 entries',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  ElevatedButton(onPressed: () {}, child: const Text('B1')),
                  ElevatedButton(onPressed: () {}, child: const Text('B2')),
                  ElevatedButton(onPressed: () {}, child: const Text('B3')),
                  ElevatedButton(onPressed: () {}, child: const Text('B4')),
                  ElevatedButton(onPressed: () {}, child: const Text('B5')),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{'limit': '3'},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final List<dynamic> candidates = decoded['candidates'] as List<dynamic>;

        expect(candidates, hasLength(3));
        expect(decoded['count'], equals(3));
      },
    );
  });

  group('extDuskObserveHandler — q-ref re-resolves on subsequent lookup', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    testWidgets(
      '(g) the minted q-ref is registered in RefRegistry and round-trips '
      'via lookupQuery (predicates carried forward for action-time re-walk)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ElevatedButton(
                onPressed: () {},
                child: const Text('LoginButton'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> first =
            (decoded['candidates'] as List<dynamic>).first
                as Map<String, dynamic>;
        final String ref = first['ref'] as String;

        // The q-ref must round-trip through lookupQuery — proves the predicate
        // set was stored and can be re-executed by a follow-up action call.
        final DuskQuery? stored = RefRegistry.lookupQuery(ref);
        expect(stored, isNotNull);
        // At least one of text/semanticsLabel/key is non-null so the predicate
        // can drive a fresh tree walk on follow-up actions.
        expect(
          stored!.text != null ||
              stored.semanticsLabel != null ||
              stored.keyValue != null,
          isTrue,
        );
      },
    );
  });

  group('extDuskObserveHandler — candidates sharing one label', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    testWidgets(
      '(h) each candidate re-resolves to the node it was minted from, not to '
      'the first node carrying that label',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Three buttons with one label, which is what a list of rows carrying
        // the same action looks like. Before `matchIndex` every candidate's
        // handle carried the label alone, so all three resolved to the first
        // and an agent acting on the third moved the first.
        final List<int> pressed = <int>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  for (int index = 0; index < 3; index++)
                    ElevatedButton(
                      onPressed: () => pressed.add(index),
                      child: const Text('Favourite'),
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final List<dynamic> candidates = (jsonDecode(response.result!)
            as Map<String, dynamic>)['candidates'] as List<dynamic>;

        expect(candidates.length, 3);

        // Every candidate resolves, and to its own node: the three entries
        // differ by their vertical position, so a handle that collapsed onto
        // the first would report the first's rect three times.
        final List<double> observed = <double>[
          for (final dynamic entry in candidates)
            ((entry as Map<String, dynamic>)['bounds']
                as Map<String, dynamic>)['y'] as double,
        ];

        final List<double> resolved = <double>[
          for (final dynamic entry in candidates)
            resolveQuery(
              RefRegistry.lookupQuery(
                (entry as Map<String, dynamic>)['ref'] as String,
              )!,
            )!
                .rect
                .top,
        ];

        expect(resolved, observed);
      },
    );

    testWidgets(
      '(i) a handle whose node is gone resolves to nothing rather than to a '
      'surviving sibling with the same label',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // The stale case the index has to keep honest. Observe three, drop one,
        // and the handle for the third must report no match: answering with
        // whichever sibling moved up would be the same silent substitution
        // this index exists to prevent, one rebuild later.
        int count = 3;
        late StateSetter setCount;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (BuildContext context, StateSetter setState) {
                  setCount = setState;

                  return Column(
                    children: <Widget>[
                      for (int index = 0; index < count; index++)
                        ElevatedButton(
                          onPressed: () {},
                          child: const Text('Favourite'),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final List<dynamic> candidates = (jsonDecode(response.result!)
            as Map<String, dynamic>)['candidates'] as List<dynamic>;
        final String last =
            (candidates.last as Map<String, dynamic>)['ref'] as String;

        setCount(() => count = 2);
        await tester.pumpAndSettle();

        expect(resolveQuery(RefRegistry.lookupQuery(last)!), isNull);
      },
    );

    testWidgets(
      '(j) the index counts nodes observe does not emit, because the resolver '
      'does',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // An inert node carrying the button's label, ahead of it in the walk.
        // Observe does not emit it, the resolver counts it, and a counter
        // living inside observe's own filter would call the button index 0
        // and resolve it to the label.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  Semantics(
                    label: 'Favourite',
                    container: true,
                    child: const SizedBox(width: 120, height: 40),
                  ),
                  Semantics(
                    label: 'Favourite',
                    button: true,
                    container: true,
                    child: const SizedBox(width: 120, height: 40),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final List<dynamic> candidates = (jsonDecode(response.result!)
            as Map<String, dynamic>)['candidates'] as List<dynamic>;

        expect(candidates.length, 1, reason: 'only the button is interactive');

        final Map<String, dynamic> only =
            candidates.single as Map<String, dynamic>;
        final double observed =
            (only['bounds'] as Map<String, dynamic>)['y'] as double;

        expect(observed, 40, reason: 'the button is the second row');
        expect(
          resolveQuery(RefRegistry.lookupQuery(only['ref'] as String)!)!
              .rect
              .top,
          observed,
        );
      },
    );
  });

  group('extDuskObserveHandler — merged semantics', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    testWidgets(
      '(k) a merging container whose data label is borrowed from a descendant '
      'does not shift the indices of the nodes that own theirs',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // The two walks that have to agree read different strings.
        // `SemanticsNode.label` is the node's own, while `getSemanticsData()`
        // concatenates every merged descendant's label when
        // `mergeAllDescendantsIntoThisNode` is set
        // (`semantics.dart:3801-3804`). So under a `MergeSemantics` whose own
        // label is empty and whose descendant supplies `Favourite`, the
        // boundary REPORTS `Favourite` while the resolver, which counts
        // `node.label`, never sees it there.
        //
        // Counted on the data label, that files three nodes under `Favourite`
        // where the resolver sees two: the plain button takes an index nothing
        // can reach and the inner one takes an index that lands on it.
        //
        // The padding is load bearing. Without it the boundary, the inner
        // button and the plain button share a y, and an assertion comparing
        // positions passes whichever node it is handed. Three distinct tops.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: <Widget>[
                  MergeSemantics(
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Semantics(
                          container: true,
                          button: true,
                          label: 'Favourite',
                          child: const SizedBox(width: 100, height: 40),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    container: true,
                    button: true,
                    label: 'Favourite',
                    child: const SizedBox(width: 100, height: 40),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final List<Map<String, dynamic>> candidates = <Map<String, dynamic>>[
          for (final dynamic entry in (jsonDecode(response.result!)
              as Map<String, dynamic>)['candidates'] as List<dynamic>)
            entry as Map<String, dynamic>,
        ];

        double topOf(Map<String, dynamic> candidate) =>
            (candidate['bounds'] as Map<String, dynamic>)['y'] as double;

        RefEntry? resolve(Map<String, dynamic> candidate) => resolveQuery(
              RefRegistry.lookupQuery(candidate['ref'] as String)!,
            );

        expect(candidates.map(topOf), <double>[0, 8, 56]);

        // The two nodes that own their label resolve to themselves. These are
        // the assertions the Major broke: counted on the merged label the
        // middle one landed on the last and the last resolved to nothing.
        expect(resolve(candidates[1])!.rect.top, 8);
        expect(resolve(candidates[2])!.rect.top, 56);

        // And the boundary, which is the case this fix deliberately does not
        // cover, written down rather than left to pass quietly. Its own label
        // is empty, so it is minted UNINDEXED against the merged data label
        // and the resolver answers it with the first interactive match, which
        // is its own descendant. That is the behaviour it had before this
        // branch; what the index changes is that it can no longer drag its
        // neighbours along with it.
        expect(
            RefRegistry.lookupQuery(candidates[0]['ref'] as String)!.matchIndex,
            isNull);
        expect(
          resolve(candidates[0])!.rect.top,
          8,
          reason: 'the unindexed boundary still answers with its descendant',
        );
      },
    );
  });

  group('extDuskObserveHandler — empty tree', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    testWidgets(
      '(h) returns empty list when no interactive widgets exist',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Text('No interactive widgets here')),
          ),
        );
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;

        expect(decoded['candidates'], isEmpty);
        expect(decoded['count'], equals(0));
      },
    );
  });

  group('extDuskObserveHandler — enricher fields', () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
    });

    testWidgets(
      '(i) default includeEnrichers projects the default subset '
      '(magicFormField present; full wind sub-fields collapsed)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        // Register fake enrichers that mimic Magic + Wind output shapes.
        DuskPlugin.enrichers.add(
          (Element element, RefRegistry refs) => 'magicFormField: email',
        );
        DuskPlugin.enrichers.add(
          (Element element, RefRegistry refs) =>
              'wind:\n  breakpoint: lg\n  brightness: light\n  '
              'platform: web\n  states: [hover]\n  bgColor: \'#3B82F6\'',
        );

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
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> first =
            (decoded['candidates'] as List<dynamic>).first
                as Map<String, dynamic>;

        // Default-subset enricher fields present.
        expect(first['magicFormField'], equals('email'));

        // Wind sub-fields filtered down to breakpoint + states only in the
        // default subset.
        final Map<String, dynamic>? wind =
            first['wind'] as Map<String, dynamic>?;
        expect(wind, isNotNull);
        expect(wind!['breakpoint'], equals('lg'));
        expect(wind['states'], equals('[hover]'));
        expect(wind.containsKey('brightness'), isFalse);
        expect(wind.containsKey('platform'), isFalse);
        expect(wind.containsKey('bgColor'), isFalse);
      },
    );

    testWidgets(
      '(j) includeEnrichers="full" projects every enricher field including '
      'the full wind sub-field block',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        DuskPlugin.enrichers.add(
          (Element element, RefRegistry refs) => 'magicFormField: email',
        );
        DuskPlugin.enrichers.add(
          (Element element, RefRegistry refs) => 'magicRouteParams: id=7,'
              'page=2',
        );
        DuskPlugin.enrichers.add(
          (Element element, RefRegistry refs) =>
              'wind:\n  breakpoint: lg\n  brightness: dark\n  '
              'bgColor: \'#3B82F6\'',
        );

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
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{'includeEnrichers': 'full'},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> first =
            (decoded['candidates'] as List<dynamic>).first
                as Map<String, dynamic>;

        expect(first['magicFormField'], equals('email'));
        expect(first['magicRouteParams'], equals('id=7,page=2'));

        final Map<String, dynamic> wind = first['wind'] as Map<String, dynamic>;
        expect(wind['breakpoint'], equals('lg'));
        expect(wind['brightness'], equals('dark'));
        expect(wind['bgColor'], equals("'#3B82F6'"));
      },
    );

    testWidgets(
      '(k) includeEnrichers="false" emits no enricher fields at all',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        DuskPlugin.enrichers.add(
          (Element element, RefRegistry refs) => 'magicFormField: email',
        );
        DuskPlugin.enrichers.add(
          (Element element, RefRegistry refs) => 'wind:\n  breakpoint: lg',
        );

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
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{'includeEnrichers': 'false'},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> first =
            (decoded['candidates'] as List<dynamic>).first
                as Map<String, dynamic>;

        expect(first.containsKey('magicFormField'), isFalse);
        expect(first.containsKey('wind'), isFalse);
      },
    );
  });

  group(
      'extDuskObserveHandler — fluttersdk_wind_diagnostics_contracts registry',
      () {
    setUp(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
      WindDebugRegistry.resetForTesting();
    });

    tearDown(() {
      RefRegistry.resetForTesting();
      DuskPlugin.enrichers.clear();
      WindDebugRegistry.resetForTesting();
    });

    testWidgets(
      '(l) when a WindDebugResolver is registered, the wind block survives '
      'in observe output without any enricher-list contribution',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        WindDebugRegistry.registerForTesting(_FakeWindResolver());

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
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> first =
            (decoded['candidates'] as List<dynamic>).first
                as Map<String, dynamic>;

        final Map<String, dynamic>? wind =
            first['wind'] as Map<String, dynamic>?;
        expect(wind, isNotNull,
            reason: 'wind block must come from WindDebugRegistry, '
                'not the enricher list');
        expect(wind!['breakpoint'], equals('lg'));
        expect(wind['states'], equals('hover'));
        expect(wind.containsKey('brightness'), isFalse,
            reason: 'defaults mode filters to _kDefaultWindKeys subset');
        expect(wind.containsKey('platform'), isFalse);
        expect(wind.containsKey('bgColor'), isFalse);
      },
    );

    testWidgets(
      '(m) includeEnrichers="full" projects all wind sub-fields from the '
      'resolver',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        WindDebugRegistry.registerForTesting(_FakeWindResolver());

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
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{'includeEnrichers': 'full'},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> first =
            (decoded['candidates'] as List<dynamic>).first
                as Map<String, dynamic>;

        final Map<String, dynamic>? wind =
            first['wind'] as Map<String, dynamic>?;
        expect(wind, isNotNull);
        expect(wind!['breakpoint'], equals('lg'));
        expect(wind['brightness'], equals('dark'));
        expect(wind['platform'], equals('web'));
        expect(wind['states'], equals('hover'));
        expect(wind['bgColor'], equals('#3B82F6'));
        expect(wind['className'], equals('flex p-4'));
      },
    );

    testWidgets(
      '(n) includeEnrichers="false" still suppresses the wind block even '
      'when a resolver is registered',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        WindDebugRegistry.registerForTesting(_FakeWindResolver());

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
        await tester.pumpAndSettle();

        final response = await extDuskObserveHandler(
          'ext.dusk.observe',
          <String, String>{'includeEnrichers': 'false'},
        );
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        final Map<String, dynamic> first =
            (decoded['candidates'] as List<dynamic>).first
                as Map<String, dynamic>;

        expect(first.containsKey('wind'), isFalse);
      },
    );
  });

  group('extDuskObserveHandler — MCP descriptor constants', () {
    test('dusk_observe MCP descriptor name is "dusk_observe"', () {
      expect(kDuskObserveMcpName, equals('dusk_observe'));
    });

    test('dusk_observe MCP descriptor extensionMethod is ext.dusk.observe', () {
      expect(kDuskObserveMcpExtension, equals('ext.dusk.observe'));
    });
  });
}
