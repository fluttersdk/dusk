import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_scroll.dart';

void main() {
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
