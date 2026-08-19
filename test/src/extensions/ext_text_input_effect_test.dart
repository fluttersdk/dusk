import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/extensions/ext_text_input.dart';
import 'package:fluttersdk_dusk/src/ref_registry.dart';

/// Verifies that the text verbs report what the widget HOLDS, not what they
/// were asked to write.
///
/// `ext.dusk.type` echoed its own `text` parameter back, so a field that
/// filtered or rejected the input reported a clean success with the value the
/// caller wanted. A number field silently dropping a fill produced a
/// defect-shaped story that survived two rewrites of the widget before anyone
/// read the field back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('aiTestTypeHandler effect', () {
    setUp(RefRegistry.resetForTesting);
    tearDown(RefRegistry.resetForTesting);

    Future<String> pumpFieldAndRegisterRef(
      WidgetTester tester, {
      List<TextInputFormatter> formatters = const <TextInputFormatter>[],
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(inputFormatters: formatters),
          ),
        ),
      );

      return RefRegistry.registerForTesting(
        rect: const Rect.fromLTWH(0, 0, 200, 40),
        element: tester.element(find.byType(TextField)),
        groupId: 'g',
        isTextField: true,
      );
    }

    testWidgets('confirms the value the field accepted', (
      WidgetTester tester,
    ) async {
      final String ref = await pumpFieldAndRegisterRef(tester);

      final Future<developer.ServiceExtensionResponse> pending =
          aiTestTypeHandler(
        'ext.dusk.type',
        <String, String>{
          'ref': ref,
          'text': 'QA Sweep User',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          'includeSnapshot': 'false',
        },
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await pending;

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      final Map<String, dynamic> effect =
          decoded['effect'] as Map<String, dynamic>;

      expect(effect['kind'], equals('text'));
      expect(effect['verified'], isTrue);
      expect(effect['value'], equals('QA Sweep User'));
    });

    testWidgets('reports verified:false when the field rejects the input', (
      WidgetTester tester,
    ) async {
      // A digits-only field is the reproducible stand-in for the real case:
      // an InputType.number field that swallowed every fill while dusk kept
      // reporting the text it had been handed.
      final String ref = await pumpFieldAndRegisterRef(
        tester,
        formatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
      );

      final Future<developer.ServiceExtensionResponse> pending =
          aiTestTypeHandler(
        'ext.dusk.type',
        <String, String>{
          'ref': ref,
          'text': 'abc',
          'checkStable': 'false',
          'checkReceivesEvents': 'false',
          'includeSnapshot': 'false',
        },
      );
      await tester.pump();
      await tester.pump();
      final developer.ServiceExtensionResponse response = await pending;

      final Map<String, dynamic> decoded =
          jsonDecode(response.result!) as Map<String, dynamic>;
      final Map<String, dynamic> effect =
          decoded['effect'] as Map<String, dynamic>;

      expect(effect['kind'], equals('text'));
      expect(
        effect['verified'],
        isFalse,
        reason: 'the field kept nothing, so the write did not land',
      );
      expect(effect['value'], equals(''));
    });
  });
}
