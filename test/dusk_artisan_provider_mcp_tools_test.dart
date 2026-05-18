import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_artisan_provider.dart';

void main() {
  group('DuskArtisanProvider.mcpTools()', () {
    late List<McpToolDescriptor> tools;

    setUp(() {
      tools = DuskArtisanProvider().mcpTools();
    });

    // -------------------------------------------------------------------------
    // Length
    // -------------------------------------------------------------------------

    test('returns exactly 6 descriptors', () {
      expect(tools, hasLength(6));
    });

    // -------------------------------------------------------------------------
    // Names
    // -------------------------------------------------------------------------

    test('contains all 6 expected tool names', () {
      final names = tools.map((t) => t.name).toList();
      expect(
        names,
        containsAll(<String>[
          'dusk_snap',
          'dusk_tap',
          'dusk_screenshot',
          'dusk_hover',
          'dusk_drag',
          'dusk_type',
        ]),
      );
    });

    // -------------------------------------------------------------------------
    // Extension methods
    // -------------------------------------------------------------------------

    test('each descriptor maps to the correct ext.dusk.* extension method', () {
      final byName = {for (final t in tools) t.name: t.extensionMethod};

      expect(byName['dusk_snap'], equals('ext.dusk.snap'));
      expect(byName['dusk_tap'], equals('ext.dusk.tap'));
      expect(byName['dusk_screenshot'], equals('ext.dusk.screenshot'));
      expect(byName['dusk_hover'], equals('ext.dusk.hover'));
      expect(byName['dusk_drag'], equals('ext.dusk.drag'));
      expect(byName['dusk_type'], equals('ext.dusk.type'));
    });

    test('no two descriptors share an extensionMethod (no overlap, no gap)',
        () {
      final methods = tools.map((t) => t.extensionMethod).toList();
      expect(methods.toSet(), hasLength(tools.length));
    });

    // -------------------------------------------------------------------------
    // Input schemas — JSON round-trip
    // -------------------------------------------------------------------------

    test('every inputSchema survives a JSON encode/decode round-trip', () {
      for (final tool in tools) {
        expect(
          () => jsonDecode(jsonEncode(tool.inputSchema)),
          returnsNormally,
          reason: '${tool.name}.inputSchema failed JSON round-trip',
        );
      }
    });

    // -------------------------------------------------------------------------
    // Required params — action tools vs passive tools
    // -------------------------------------------------------------------------

    test('dusk_tap declares ref as required', () {
      final tap = tools.firstWhere((t) => t.name == 'dusk_tap');
      final required = tap.inputSchema['required'] as List<dynamic>;
      expect(required, contains('ref'));
    });

    test('dusk_hover declares ref as required', () {
      final hover = tools.firstWhere((t) => t.name == 'dusk_hover');
      final required = hover.inputSchema['required'] as List<dynamic>;
      expect(required, contains('ref'));
    });

    test('dusk_drag declares startRef and endRef as required', () {
      final drag = tools.firstWhere((t) => t.name == 'dusk_drag');
      final required = drag.inputSchema['required'] as List<dynamic>;
      expect(required, containsAll(<String>['startRef', 'endRef']));
    });

    test('dusk_type declares ref and text as required', () {
      final type = tools.firstWhere((t) => t.name == 'dusk_type');
      final required = type.inputSchema['required'] as List<dynamic>;
      expect(required, containsAll(<String>['ref', 'text']));
    });

    test('dusk_snap does not declare required params', () {
      final snap = tools.firstWhere((t) => t.name == 'dusk_snap');
      expect(snap.inputSchema.containsKey('required'), isFalse);
    });

    test('dusk_screenshot does not declare required params', () {
      final screenshot = tools.firstWhere((t) => t.name == 'dusk_screenshot');
      expect(screenshot.inputSchema.containsKey('required'), isFalse);
    });
  });
}
