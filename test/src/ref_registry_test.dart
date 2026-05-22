import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/ref_registry.dart';

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

      final r1 = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'g',
        isTextField: false,
      );
      final r2 = RefRegistry.registerForTesting(
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

      final r = RefRegistry.registerForTesting(
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

      final keep = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'keep',
        isTextField: false,
      );
      final drop = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'drop',
        isTextField: false,
      );

      RefRegistry.disposeGroup('drop');
      expect(RefRegistry.lookup(keep), isNotNull);
      expect(RefRegistry.lookup(drop), isNull);
    });

    testWidgets('is a no-op when groupId matches nothing', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      final r = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'live',
        isTextField: false,
      );
      RefRegistry.disposeGroup('non-existent');
      expect(RefRegistry.lookup(r), isNotNull);
    });
  });

  group('refsForGroup', () {
    testWidgets('returns the refs scoped to a groupId', (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'gA',
        isTextField: false,
      );
      RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'gA',
        isTextField: false,
      );
      RefRegistry.registerForTesting(
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
      final q1 = RefRegistry.registerQuery(const DuskQuery(text: 'hello'));
      final q2 = RefRegistry.registerQuery(
        const DuskQuery(semanticsLabel: 'label'),
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
    testWidgets('clears every entry, query, and resets the counter',
        (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      final element = bareElement(tester);

      final r = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'g',
        isTextField: false,
      );
      final q = RefRegistry.registerQuery(const DuskQuery(text: 'x'));
      expect(RefRegistry.lookup(r), isNotNull);
      expect(RefRegistry.lookupQuery(q), isNotNull);

      RefRegistry.disposeAll();
      expect(RefRegistry.lookup(r), isNull);
      expect(RefRegistry.lookupQuery(q), isNull);

      // Counter reset → next mint produces e1 / q1 again.
      final r2 = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 10, 10),
        element: element,
        groupId: 'g',
        isTextField: false,
      );
      expect(r2, equals('e1'));
      final q2 = RefRegistry.registerQuery(const DuskQuery(text: 'x'));
      expect(q2, equals('q1'));
    });
  });

  group('RefRegistry.instance sentinel', () {
    test('is a non-null singleton', () {
      expect(RefRegistry.instance, isNotNull);
    });
  });
}
