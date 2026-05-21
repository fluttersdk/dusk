import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';
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

  group('extDuskObserveHandler — fluttersdk_wind_diagnostics_contracts registry', () {
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
