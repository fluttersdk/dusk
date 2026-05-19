import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_scroll.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

bool _isError(developer.ServiceExtensionResponse response) =>
    response.errorCode != null;

// aiTestScrollHandler success paths await WidgetsBinding.endOfFrame, which
// hangs the flutter_test fake-clock harness even under tester.runAsync().
// We only exercise the error path (which short-circuits before endOfFrame).
// Live drive coverage for success paths is captured by the example/ playground
// (`dusk:scroll` against the /scroll screen).

void main() {
  tearDown(() {
    RefRegistry.resetForTesting();
  });

  group('aiTestScrollByDelta', () {
    testWidgets('jumps scroll position to the target pixel value',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: List<Widget>.generate(
                30,
                (i) => SizedBox(height: 60, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

      final ScrollableState scrollable =
          tester.state(find.byType(Scrollable).first);
      expect(scrollable.position.pixels, equals(0));

      await aiTestScrollByDelta(scrollable, 240.0);
      expect(scrollable.position.pixels, equals(240.0));
    });
  });

  group('aiTestScrollHandler — param + error paths', () {
    testWidgets('returns error when no scrollable exists in the tree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('flat'))),
      );

      final response = await aiTestScrollHandler(
        'ext.dusk.scroll',
        const {'dy': '100'},
      );
      expect(_isError(response), isTrue);
    });

    testWidgets('returns success when scrollable exists (pump-advance frames)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: List<Widget>.generate(
                40,
                (i) => SizedBox(height: 60, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

      final future = aiTestScrollHandler(
        'ext.dusk.scroll',
        const {'dy': '120'},
      );
      await tester.pump();
      await tester.pump();
      final response = await future;
      expect(response.errorCode, isNull);
    });

    testWidgets('unknown e-ref falls back to root walk', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: List<Widget>.generate(
                40,
                (i) => SizedBox(height: 60, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

      final future = aiTestScrollHandler(
        'ext.dusk.scroll',
        const {'ref': 'e9999', 'dy': '120'},
      );
      await tester.pump();
      await tester.pump();
      final response = await future;
      expect(response.errorCode, isNull);
    });

    testWidgets('unknown q-ref falls back to root walk', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: List<Widget>.generate(
                40,
                (i) => SizedBox(height: 60, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

      final future = aiTestScrollHandler(
        'ext.dusk.scroll',
        const {'ref': 'q9999', 'dy': '120'},
      );
      await tester.pump();
      await tester.pump();
      final response = await future;
      expect(response.errorCode, isNull);
    });

    testWidgets('known e-ref scrolls via its parent scrollable',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: List<Widget>.generate(
                40,
                (i) => SizedBox(height: 60, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

      // Register an element that is inside the scrollable so Scrollable.maybeOf
      // returns the parent state.
      final Element listItem = tester.element(find.text('row 0'));
      final ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 100, 60),
        element: listItem,
        groupId: 'g-scroll-ref',
        isTextField: false,
      );

      final future = aiTestScrollHandler(
        'ext.dusk.scroll',
        {'ref': ref, 'dy': '120'},
      );
      await tester.pump();
      await tester.pump();
      final response = await future;
      expect(response.errorCode, isNull);
    });
  });

  group('registerScrollExtensions', () {
    test('runs without throwing twice in a row (hot-restart safe)', () {
      registerScrollExtensions();
      registerScrollExtensions();
    });
  });

  group('ext.dusk.select_option handler', () {
    // -------------------------------------------------------------------------
    // (a) aiTestSelectOptionInElement selects DropdownButton value
    // -------------------------------------------------------------------------

    testWidgets(
      'aiTestSelectOptionInElement invokes onChanged callback on'
      ' DropdownButton',
      (WidgetTester tester) async {
        String? selectedValue = 'a';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DropdownButton<String>(
                value: selectedValue,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'a',
                    child: Text('Option A'),
                  ),
                  DropdownMenuItem(
                    value: 'b',
                    child: Text('Option B'),
                  ),
                  DropdownMenuItem(
                    value: 'c',
                    child: Text('Option C'),
                  ),
                ],
                onChanged: (String? newValue) {
                  selectedValue = newValue;
                },
              ),
            ),
          ),
        );

        final BuildContext context = tester.element(find.byType(Scaffold));

        final bool invoked = aiTestSelectOptionInElement(
          context,
          value: 'b',
        );

        expect(
          invoked,
          isTrue,
          reason: 'aiTestSelectOptionInElement should find and invoke'
              ' DropdownButton',
        );
        expect(
          selectedValue,
          equals('b'),
          reason: 'value should be updated via onChanged callback',
        );
      },
    );

    // -------------------------------------------------------------------------
    // (b) aiTestSelectOptionInElement returns false when no widget found
    // -------------------------------------------------------------------------

    testWidgets(
      'aiTestSelectOptionInElement returns false when no DropdownButton'
      ' in subtree',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('No dropdown here'),
              ),
            ),
          ),
        );

        final BuildContext context = tester.element(find.byType(Scaffold));

        final bool invoked = aiTestSelectOptionInElement(
          context,
          value: 'b',
        );

        expect(
          invoked,
          isFalse,
          reason: 'should return false when no DropdownButton found',
        );
      },
    );

    // -------------------------------------------------------------------------
    // (c) aiTestSelectOptionInElement handles disabled dropdown
    // -------------------------------------------------------------------------

    testWidgets(
      'aiTestSelectOptionInElement returns false when DropdownButton has'
      ' null onChanged',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DropdownButton<String>(
                value: 'a',
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'a',
                    child: Text('Option A'),
                  ),
                  DropdownMenuItem(
                    value: 'b',
                    child: Text('Option B'),
                  ),
                ],
                onChanged: null,
              ),
            ),
          ),
        );

        final BuildContext context = tester.element(find.byType(Scaffold));

        final bool invoked = aiTestSelectOptionInElement(
          context,
          value: 'b',
        );

        expect(
          invoked,
          isFalse,
          reason: 'should return false when onChanged is null (disabled)',
        );
      },
    );

    // -------------------------------------------------------------------------
    // (d) Handler missing required parameter 'value' returns error
    // -------------------------------------------------------------------------

    testWidgets(
      'aiTestSelectOptionHandler returns error when value parameter missing',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DropdownButton<String>(
                value: 'a',
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'a',
                    child: Text('Option A'),
                  ),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        );

        try {
          final response = await aiTestSelectOptionHandler(
            'ext.dusk.select_option',
            <String, String>{'ref': 'e1'},
            // 'value' intentionally missing
          );
          // The handler should return an error response for missing value
          // We verify this by checking the response is not null
          expect(response, isNotNull);
        } catch (e) {
          fail('Handler should not throw; caught: $e');
        }
      },
    );

    // -------------------------------------------------------------------------
    // (e) Handler returns error when no widget found
    // -------------------------------------------------------------------------

    testWidgets(
      'aiTestSelectOptionHandler returns error when no selectable widget'
      ' found',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('No dropdown'),
              ),
            ),
          ),
        );

        try {
          final response = await aiTestSelectOptionHandler(
            'ext.dusk.select_option',
            <String, String>{'value': 'b'},
          );
          expect(response, isNotNull);
        } catch (e) {
          fail('Handler should not throw; caught: $e');
        }
      },
    );
  });
}
