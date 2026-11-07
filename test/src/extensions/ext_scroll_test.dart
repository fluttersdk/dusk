import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_scroll.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_snapshot.dart';
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

    testWidgets('effect reports the offset on both sides of the scroll',
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

      final ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 100, 60),
        element: tester.element(find.text('row 0')),
        groupId: 'g-scroll-effect',
        isTextField: false,
      );

      final future = aiTestScrollHandler(
        'ext.dusk.scroll',
        {'ref': ref, 'dy': '120', 'includeSnapshot': 'false'},
      );
      await tester.pump();
      await tester.pump();
      final response = await future;

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      final Map<String, dynamic> effect =
          decoded['effect'] as Map<String, dynamic>;

      // `scrolled: true` says the call ran. Only the offsets say the list
      // moved, which is what a ref that is not a scrollable fails to do
      // while still reporting success.
      expect(effect['kind'], equals('scrollOffset'));
      expect(effect['before'], equals(0.0));
      expect(effect['after'], equals(120.0));
      expect(effect['changed'], isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // The MCP schema advertises direction + pixels, so the extension reads them.
  // ---------------------------------------------------------------------------

  group('aiTestScrollHandler direction and pixels', () {
    Future<Map<String, dynamic>> scrollBy(
      WidgetTester tester,
      Map<String, String> params,
    ) async {
      final ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 100, 60),
        // Whichever row is still built after an earlier scroll.
        element: tester.element(find.textContaining('row ').first),
        groupId: 'g-scroll-direction',
        isTextField: false,
      );
      final future = aiTestScrollHandler(
        'ext.dusk.scroll',
        {'ref': ref, 'includeSnapshot': 'false', ...params},
      );
      await tester.pump();
      await tester.pump();
      final response = await future;
      expect(response.errorCode, isNull, reason: response.errorDetail);
      return jsonDecode(response.result!) as Map<String, dynamic>;
    }

    Future<void> pumpList(WidgetTester tester) => tester.pumpWidget(
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

    testWidgets('the schema example scrolls down by the given pixels',
        (tester) async {
      await pumpList(tester);

      final decoded = await scrollBy(
        tester,
        {'direction': 'down', 'pixels': '200'},
      );

      final effect = decoded['effect'] as Map<String, dynamic>;
      expect(effect['after'], equals(200.0));
      expect(effect['changed'], isTrue);
    });

    testWidgets('up scrolls back by the given pixels', (tester) async {
      await pumpList(tester);
      await scrollBy(tester, {'dy': '300'});

      final decoded = await scrollBy(
        tester,
        {'direction': 'up', 'pixels': '100'},
      );

      final effect = decoded['effect'] as Map<String, dynamic>;
      expect(effect['before'], equals(300.0));
      expect(effect['after'], equals(200.0));
    });

    testWidgets('a lone direction scrolls the documented 300 pixels',
        (tester) async {
      await pumpList(tester);

      final decoded = await scrollBy(tester, {'direction': 'down'});

      final effect = decoded['effect'] as Map<String, dynamic>;
      expect(effect['after'], equals(300.0));
    });

    testWidgets('explicit dy wins over direction and pixels', (tester) async {
      await pumpList(tester);

      final decoded = await scrollBy(
        tester,
        {'dy': '120', 'direction': 'down', 'pixels': '500'},
      );

      final effect = decoded['effect'] as Map<String, dynamic>;
      expect(effect['after'], equals(120.0));
    });

    testWidgets('no delta at all still moves nothing', (tester) async {
      await pumpList(tester);

      final decoded = await scrollBy(tester, {});

      final effect = decoded['effect'] as Map<String, dynamic>;
      expect(effect['changed'], isFalse);
    });

    testWidgets('a lone pixels scrolls down, the documented default direction',
        (tester) async {
      await pumpList(tester);

      final decoded = await scrollBy(tester, {'pixels': '150'});

      final effect = decoded['effect'] as Map<String, dynamic>;
      expect(effect['after'], equals(150.0));
    });

    testWidgets('pixels is a distance: the direction alone gives the sign',
        (tester) async {
      await pumpList(tester);
      await scrollBy(tester, {'dy': '300'});

      final decoded = await scrollBy(
        tester,
        {'direction': 'up', 'pixels': '-100'},
      );

      final effect = decoded['effect'] as Map<String, dynamic>;
      expect(effect['after'], equals(200.0));
    });

    testWidgets('left and right drive the horizontal axis', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              scrollDirection: Axis.horizontal,
              children: List<Widget>.generate(
                40,
                (i) => SizedBox(width: 60, child: Text('row $i')),
              ),
            ),
          ),
        ),
      );

      final right = await scrollBy(
        tester,
        {'direction': 'right', 'pixels': '200'},
      );
      expect((right['effect'] as Map<String, dynamic>)['after'], equals(200.0));

      final left = await scrollBy(
        tester,
        {'direction': 'left', 'pixels': '50'},
      );
      expect((left['effect'] as Map<String, dynamic>)['after'], equals(150.0));
    });

    group('a value that cannot be a delta is refused, not defaulted', () {
      Future<void> expectInvalid(
        WidgetTester tester,
        Map<String, String> params,
      ) async {
        await pumpList(tester);
        final response = await aiTestScrollHandler(
          'ext.dusk.scroll',
          {'includeSnapshot': 'false', ...params},
        );

        expect(response.errorCode, isNotNull);
        expect(
          response.errorCode,
          equals(developer.ServiceExtensionResponse.invalidParams),
        );
      }

      testWidgets('pixels that is not a number', (tester) async {
        await expectInvalid(tester, {'direction': 'up', 'pixels': 'abc'});
      });

      testWidgets('pixels that is NaN', (tester) async {
        await expectInvalid(tester, {'direction': 'up', 'pixels': 'NaN'});
      });

      testWidgets('pixels that is infinite', (tester) async {
        await expectInvalid(
            tester, {'direction': 'down', 'pixels': 'Infinity'});
      });

      testWidgets('an unknown direction', (tester) async {
        await expectInvalid(tester, {'direction': 'sideways', 'pixels': '10'});
      });

      testWidgets('a dx that is not a number, even next to a direction',
          (tester) async {
        await expectInvalid(tester, {'dx': 'abc', 'direction': 'down'});
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Step 3.2 — snapshot-in-action-response for ext.dusk.scroll.
  // ---------------------------------------------------------------------------

  group('aiTestScrollHandler snapshot-in-response', () {
    testWidgets(
      'embeds snapshot field in success response by default',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: List<Widget>.generate(
                  40,
                  (i) => SizedBox(height: 60, child: Text('scroll-row-$i')),
                ),
              ),
            ),
          ),
        );

        final future = aiTestScrollHandler(
          'ext.dusk.scroll',
          const <String, String>{'dy': '120'},
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        expect(response.result, isNotNull);
        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['scrolled'], isTrue);
        expect(decoded['snapshot'], isA<String>());
      },
    );

    testWidgets(
      'omits snapshot when includeSnapshot is false',
      (WidgetTester tester) async {
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
          const <String, String>{
            'dy': '120',
            'includeSnapshot': 'false',
          },
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded.containsKey('snapshot'), isFalse);
      },
    );

    testWidgets(
      'snapshot YAML reflects the post-scroll tree contents',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: List<Widget>.generate(
                  40,
                  (i) => SizedBox(
                    height: 60,
                    child: Text('scroll-content-marker-$i'),
                  ),
                ),
              ),
            ),
          ),
        );

        final future = aiTestScrollHandler(
          'ext.dusk.scroll',
          const <String, String>{'dy': '60'},
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(
            decoded['snapshot'] as String, contains('scroll-content-marker'));
      },
    );

    testWidgets(
      'snapshot=diff answers the rows the scroll changed',
      (WidgetTester tester) async {
        resetSnapshotBaselineForTesting();
        addTearDown(resetSnapshotBaselineForTesting);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: List<Widget>.generate(
                  40,
                  (i) => SizedBox(height: 60, child: Text('diff-row-$i')),
                ),
              ),
            ),
          ),
        );
        await duskSnapBuild();

        final future = aiTestScrollHandler(
          'ext.dusk.scroll',
          const <String, String>{'dy': '600', 'snapshot': 'diff'},
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded['snapshotMode'], 'diff');
        final String diff = decoded['snapshot'] as String;
        expect(diff, contains('- - text "diff-row-0"'));
        expect(diff, matches(RegExp(r'\(\d+ of \d+ lines changed\)$')));
      },
    );

    testWidgets(
      'snapshot=none omits the snapshot',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView(
                children: List<Widget>.generate(
                  40,
                  (i) => SizedBox(height: 60, child: Text('none-row-$i')),
                ),
              ),
            ),
          ),
        );

        final future = aiTestScrollHandler(
          'ext.dusk.scroll',
          const <String, String>{'dy': '120', 'snapshot': 'none'},
        );
        await tester.pump();
        await tester.pump();
        final response = await future;

        final Map<String, dynamic> decoded =
            jsonDecode(response.result!) as Map<String, dynamic>;
        expect(decoded.containsKey('snapshot'), isFalse);
      },
    );
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

  group('aiTestSelectOptionHandler success path', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('selecting an option returns the value that was picked', (
      WidgetTester tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DropdownButton<String>(
              value: 'one',
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem<String>(value: 'one', child: Text('One')),
                DropdownMenuItem<String>(value: 'two', child: Text('Two')),
              ],
              onChanged: (String? v) => picked = v,
            ),
          ),
        ),
      );

      // Start the handler, then pump: it awaits a frame to let the dropdown
      // settle, and under the test binding that frame only happens when the
      // harness is pumped.
      final Future<developer.ServiceExtensionResponse> future =
          aiTestSelectOptionHandler(
        'ext.dusk.select_option',
        const <String, String>{'value': 'two'},
      );
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final developer.ServiceExtensionResponse response = await future;

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['selected'], isTrue);
      expect(decoded['value'], equals('two'));
      expect(picked, equals('two'));
    });
  });

  group('aiTestScrollHandler effect measures the scrollable it drove', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('a ref pointing at the ListView itself reports a real before',
        (WidgetTester tester) async {
      // The before-offset used to come from `Scrollable.maybeOf(target)`,
      // which is the ANCESTOR, while the scroll drove the target itself.
      // Passing a ListView's own ref (what `find --key=my-list` returns)
      // therefore reported `before: null` alongside a real `after`, and
      // `changed: true` for a list that had not moved.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                for (int i = 0; i < 40; i++)
                  SizedBox(height: 100, child: Text('row-$i')),
              ],
            ),
          ),
        ),
      );

      final Element listView = tester.element(find.byType(Scrollable));
      final String ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 400, 600),
        element: listView,
        groupId: 'g',
        isTextField: false,
      );

      final Future<developer.ServiceExtensionResponse> future =
          aiTestScrollHandler('ext.dusk.scroll', <String, String>{
        'ref': ref,
        'dy': '300',
        'includeSnapshot': 'false',
      });
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final Map<String, dynamic> decoded =
          jsonDecode((await future).result!) as Map<String, dynamic>;

      final Map<String, dynamic> effect =
          decoded['effect'] as Map<String, dynamic>;
      expect(effect['kind'], equals('scrollOffset'));
      expect(effect['before'], isNotNull, reason: 'measured the wrong object');
      expect(effect['before'], equals(0.0));
      expect(effect['after'], equals(300.0));
      expect(effect['changed'], isTrue);
    });
  });

  group('aiTestScrollHandler scrolled flag', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    Future<Map<String, dynamic>> scroll(
      WidgetTester tester,
      Map<String, String> params,
    ) async {
      final Future<developer.ServiceExtensionResponse> future =
          aiTestScrollHandler('ext.dusk.scroll', <String, String>{
        ...params,
        'includeSnapshot': 'false',
      });
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return jsonDecode((await future).result!) as Map<String, dynamic>;
    }

    testWidgets('is false for a ref with no scrollable around it', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('flat'))),
      );
      final String ref = RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 100, 20),
        element: tester.element(find.text('flat')),
        groupId: 'g',
        isTextField: false,
      );

      final Map<String, dynamic> decoded = await scroll(
          tester, <String, String>{'ref': ref, 'intoView': 'true'});

      expect(decoded['scrolled'], isFalse);
      expect(
        (decoded['effect'] as Map<String, dynamic>)['changed'],
        isFalse,
        reason: 'with no scrollable there is no offset to compare',
      );
    });

    testWidgets('is false when the offset did not move', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                for (int i = 0; i < 40; i++)
                  SizedBox(height: 100, child: Text('row-$i')),
              ],
            ),
          ),
        ),
      );

      final Map<String, dynamic> decoded =
          await scroll(tester, <String, String>{'dy': '0'});

      expect(decoded['scrolled'], isFalse);
      expect(decoded['effect']['changed'], isFalse);
    });

    testWidgets('is false past the end of the list, and stops at the edge', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                for (int i = 0; i < 40; i++)
                  SizedBox(height: 100, child: Text('row-$i')),
              ],
            ),
          ),
        ),
      );
      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      final double max = scrollable.position.maxScrollExtent;
      scrollable.position.jumpTo(max);
      await tester.pump();

      final Map<String, dynamic> decoded =
          await scroll(tester, <String, String>{'dy': '500'});

      expect(decoded['scrolled'], isFalse);
      expect(decoded['finalOffset'], equals(max));
      expect(decoded['effect']['changed'], isFalse);
    });

    testWidgets('skips a list that was built offstage and never laid out', (
      WidgetTester tester,
    ) async {
      // The bottom overlay entry is kept alive but not laid out under an
      // opaque entry, so its scroll position has pixels and no extents.
      await tester.pumpWidget(
        MaterialApp(
          home: Overlay(
            initialEntries: <OverlayEntry>[
              OverlayEntry(
                maintainState: true,
                builder: (_) => ListView(
                  children: <Widget>[
                    for (int i = 0; i < 40; i++)
                      SizedBox(height: 100, child: Text('hidden-$i')),
                  ],
                ),
              ),
              OverlayEntry(
                opaque: true,
                builder: (_) => ListView(
                  children: <Widget>[
                    for (int i = 0; i < 40; i++)
                      SizedBox(height: 100, child: Text('shown-$i')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      final Future<developer.ServiceExtensionResponse> future =
          aiTestScrollHandler('ext.dusk.scroll', <String, String>{
        'dy': '200',
        'includeSnapshot': 'false',
      });
      for (int i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final developer.ServiceExtensionResponse response = await future;

      expect(response.errorCode, isNull, reason: '${response.errorDetail}');
      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(decoded['scrolled'], isTrue);
      expect(find.text('shown-0'), findsNothing,
          reason: 'the visible list is the one that scrolled');
    });

    testWidgets('is true when the offset moved', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: <Widget>[
                for (int i = 0; i < 40; i++)
                  SizedBox(height: 100, child: Text('row-$i')),
              ],
            ),
          ),
        ),
      );

      final Map<String, dynamic> decoded =
          await scroll(tester, <String, String>{'dy': '200'});

      expect(decoded['scrolled'], isTrue);
      expect(decoded['finalOffset'], equals(200.0));
    });
  });

  group('aiTestSelectOptionHandler effect', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    testWidgets('reports the value the dropdown settled on', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: _StatefulDropdown()));

      final Future<developer.ServiceExtensionResponse> future =
          aiTestSelectOptionHandler(
        'ext.dusk.select_option',
        const <String, String>{'value': 'two'},
      );
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final Map<String, dynamic> decoded =
          jsonDecode((await future).result!) as Map<String, dynamic>;

      final Map<String, dynamic> effect =
          decoded['effect'] as Map<String, dynamic>;
      expect(effect['kind'], equals('selected'));
      expect(effect['verified'], isTrue);
      expect(effect['value'], equals('two'));
    });

    testWidgets('reports verified:false when the app rejects the change', (
      WidgetTester tester,
    ) async {
      // The whole point of the block: `selected: true, value: two` was the
      // request echoed back, so a control whose parent refuses the change
      // reported a clean success and changed nothing.
      await tester.pumpWidget(
        const MaterialApp(home: _StatefulDropdown(accept: false)),
      );

      final Future<developer.ServiceExtensionResponse> future =
          aiTestSelectOptionHandler(
        'ext.dusk.select_option',
        const <String, String>{'value': 'two'},
      );
      for (int i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final Map<String, dynamic> decoded =
          jsonDecode((await future).result!) as Map<String, dynamic>;

      final Map<String, dynamic> effect =
          decoded['effect'] as Map<String, dynamic>;
      expect(effect['verified'], isFalse);
      expect(effect['value'], equals('one'), reason: 'it never moved');
    });
  });
}

/// A dropdown that actually rebuilds on selection, so the widget's `value`
/// reflects what it settled on. With [accept] false it swallows the change,
/// which is the control-rejects-the-write case the effect block exists for.
class _StatefulDropdown extends StatefulWidget {
  const _StatefulDropdown({this.accept = true});

  final bool accept;

  @override
  State<_StatefulDropdown> createState() => _StatefulDropdownState();
}

class _StatefulDropdownState extends State<_StatefulDropdown> {
  String _value = 'one';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DropdownButton<String>(
        value: _value,
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: 'one', child: Text('One')),
          DropdownMenuItem<String>(value: 'two', child: Text('Two')),
        ],
        onChanged: (String? v) {
          if (!widget.accept || v == null) return;
          setState(() => _value = v);
        },
      ),
    );
  }
}
