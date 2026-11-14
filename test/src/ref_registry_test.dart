import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/ref_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(RefRegistry.resetForTesting);
  tearDown(RefRegistry.resetForTesting);

  Element bareElement(WidgetTester tester) {
    return tester.element(find.byType(SizedBox));
  }

  group('register (no SemanticsNode)', () {
    testWidgets('mints a fresh e-ref each call', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      final r1 = registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'g',
        isTextField: false,
      );
      final r2 = registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'g',
        isTextField: false,
      );

      expect(r1, isNot(equals(r2)));
      expect(r1.startsWith('e'), isTrue);
      expect(r2.startsWith('e'), isTrue);
    });

    testWidgets('lookup returns the registered entry', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      final r = registerRefForTesting(
        rect: const Rect.fromLTWH(5, 5, 50, 50),
        element: element,
        groupId: 'g1',
        isTextField: true,
      );
      final entry = RefRegistry.lookup(r);
      expect(entry, isNotNull);
      expect(entry!.isTextField, isTrue);
      expect(entry.groupId, equals('g1'));
      expect(entry.rect.left, equals(5));
    });

    testWidgets('lookup returns null for unknown token', (tester) async {
      expect(RefRegistry.lookup('e9999'), isNull);
    });
  });

  group('disposeGroup', () {
    testWidgets('removes entries whose groupId matches', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      final keep = registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'keep',
        isTextField: false,
      );
      final drop = registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'drop',
        isTextField: false,
      );

      disposeRefGroup('drop');
      expect(RefRegistry.lookup(keep), isNotNull);
      expect(RefRegistry.lookup(drop), isNull);
    });

    testWidgets('is a no-op when groupId matches nothing', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      final r = registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'live',
        isTextField: false,
      );
      disposeRefGroup('non-existent');
      expect(RefRegistry.lookup(r), isNotNull);
    });
  });

  group('refsForGroup', () {
    testWidgets('returns the refs scoped to a groupId', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'gA',
        isTextField: false,
      );
      registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'gA',
        isTextField: false,
      );
      registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'gB',
        isTextField: false,
      );

      final refsA = RefRegistry.refsForGroup('gA');
      final refsB = RefRegistry.refsForGroup('gB');
      expect(refsA.length, equals(2));
      expect(refsB.length, equals(1));
    });
  });

  group('registerQuery + lookupQuery', () {
    test('mints a fresh q-ref per call and stores the predicates', () {
      final q1 = RefRegistry.registerQuery(const TapirQuery(text: 'hello'));
      final q2 = RefRegistry.registerQuery(
        const TapirQuery(semanticsLabel: 'label'),
      );
      expect(q1, startsWith('q'));
      expect(q2, startsWith('q'));
      expect(q1, isNot(equals(q2)));

      expect(RefRegistry.lookupQuery(q1)?.text, equals('hello'));
      expect(RefRegistry.lookupQuery(q2)?.semanticsLabel, equals('label'));
    });

    test('returns null for unknown query token', () {
      expect(RefRegistry.lookupQuery('q9999'), isNull);
    });
  });

  group('disposeAll', () {
    testWidgets('clears every entry, query, and resets the counter', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      final r = registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'g',
        isTextField: false,
      );
      final q = RefRegistry.registerQuery(const TapirQuery(text: 'x'));
      expect(RefRegistry.lookup(r), isNotNull);
      expect(RefRegistry.lookupQuery(q), isNotNull);

      RefRegistry.disposeAll();
      expect(RefRegistry.lookup(r), isNull);
      expect(RefRegistry.lookupQuery(q), isNull);

      // Counter reset → next mint produces e1 / q1 again.
      final r2 = registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'g',
        isTextField: false,
      );
      expect(r2, equals('e1'));
      final q2 = RefRegistry.registerQuery(const TapirQuery(text: 'x'));
      expect(q2, equals('q1'));
    });
  });

  group('bindings', () {
    const RefBinding binding = RefBinding(
      query: TapirQuery(semanticsLabel: 'Save', matchIndex: 1),
      matchCount: 2,
    );

    String mint(Element element, {String groupId = 'g'}) {
      return registerRefForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: groupId,
        isTextField: false,
      );
    }

    group('.bind()', () {
      testWidgets('stores the binding lookupBinding answers', (tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final String ref = mint(bareElement(tester));

        RefRegistry.bind(ref, binding);

        final RefBinding? stored = RefRegistry.lookupBinding(ref);
        expect(stored, isNotNull);
        expect(stored!.query.semanticsLabel, equals('Save'));
        expect(stored.query.matchIndex, equals(1));
        expect(stored.matchCount, equals(2));
      });

      testWidgets('keeps the minting route, held weakly', (tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final String ref = mint(bareElement(tester));
        final Route<dynamic> route = PageRouteBuilder<void>(
          pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) => const SizedBox.shrink(),
        );

        RefRegistry.bind(
          ref,
          RefBinding(
            query: binding.query,
            matchCount: binding.matchCount,
            route: WeakReference<Route<dynamic>>(route),
          ),
        );

        final RefBinding? stored = RefRegistry.lookupBinding(ref);
        expect(stored!.route, isA<WeakReference<Route<dynamic>>>());
        expect(stored.route!.target, same(route));
        expect(RefRegistry.lookupBinding(ref)!.query.matchIndex, equals(1));
      });

      testWidgets('a binding built without a route carries none', (
        tester,
      ) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final String ref = mint(bareElement(tester));

        RefRegistry.bind(ref, binding);

        expect(RefRegistry.lookupBinding(ref)!.route, isNull);
      });

      testWidgets('a null binding clears the one stored before', (
        tester,
      ) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final String ref = mint(bareElement(tester));

        RefRegistry.bind(ref, binding);
        RefRegistry.bind(ref, null);

        expect(RefRegistry.lookupBinding(ref), isNull);
      });
    });

    group('.rebind()', () {
      testWidgets('swaps the entry under the same token and group', (
        tester,
      ) async {
        await tester.pumpWidget(
          const Column(
            children: <Widget>[
              SizedBox(width: 1, height: 1),
              SizedBox(width: 2, height: 2),
            ],
          ),
        );
        final List<Element> elements = tester
            .elementList(find.byType(SizedBox))
            .toList();
        final String ref = mint(elements.first, groupId: 'snapshot-1');

        RefRegistry.rebind(
          ref,
          RefEntry(
            rect: const Rect.fromLTWH(4, 4, 2, 2),
            element: elements.last,
            groupId: '__query__',
            isTextField: false,
          ),
        );

        final RefEntry? entry = RefRegistry.lookup(ref);
        expect(entry!.element, same(elements.last));
        expect(entry.rect, equals(const Rect.fromLTWH(4, 4, 2, 2)));
        expect(entry.groupId, equals('snapshot-1'));
        expect(RefRegistry.refsForGroup('snapshot-1'), equals(<String>[ref]));
      });

      testWidgets('does not mint an unknown token', (tester) async {
        await tester.pumpWidget(const SizedBox.shrink());

        RefRegistry.rebind(
          'e42',
          RefEntry(
            rect: Rect.zero,
            element: bareElement(tester),
            groupId: 'g',
            isTextField: false,
          ),
        );

        expect(RefRegistry.lookup('e42'), isNull);
      });
    });

    group('clearing', () {
      testWidgets('disposeGroup drops the binding with its ref', (
        tester,
      ) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final String keep = mint(bareElement(tester), groupId: 'keep');
        final String drop = mint(bareElement(tester), groupId: 'drop');
        RefRegistry.bind(keep, binding);
        RefRegistry.bind(drop, binding);

        disposeRefGroup('drop');

        expect(RefRegistry.lookupBinding(drop), isNull);
        expect(RefRegistry.lookupBinding(keep), isNotNull);
      });

      testWidgets('resetForTesting drops every binding', (tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final String ref = mint(bareElement(tester));
        RefRegistry.bind(ref, binding);

        RefRegistry.resetForTesting();

        expect(RefRegistry.lookupBinding(ref), isNull);
      });
    });
  });

  group('RefRegistry.instance sentinel', () {
    test('is a non-null singleton', () {
      expect(RefRegistry.instance, isNotNull);
    });
  });
}
