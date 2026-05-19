import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_artisan_provider.dart';

void main() {
  group('DuskArtisanProvider.commands()', () {
    late List<ArtisanCommand> cmds;

    setUp(() {
      cmds = DuskArtisanProvider().commands();
    });

    test('returns exactly 10 commands', () {
      expect(cmds, hasLength(10));
    });

    test(
        'contains the 3 V1 commands plus the install command plus 6 alpha-2 '
        'commands (DuskDoctorCommand is intentionally absent until Step 21)',
        () {
      final names = cmds.map((c) => c.runtimeType.toString()).toSet();
      expect(
        names,
        containsAll(<String>[
          'DuskSnapCommand',
          'DuskTapCommand',
          'DuskScreenshotCommand',
          'DuskInstallCommand',
          'DuskTypeCommand',
          'DuskScrollCommand',
          'DuskWaitCommand',
          'DuskHoverCommand',
          'DuskDragCommand',
          'DuskModalCommand',
        ]),
      );
    });

    test('does not yet ship DuskDoctorCommand (lands in Step 21)', () {
      final names = cmds.map((c) => c.runtimeType.toString()).toSet();
      expect(names, isNot(contains('DuskDoctorCommand')));
    });
  });

  group('DuskArtisanProvider.mcpTools()', () {
    late List<McpToolDescriptor> tools;

    setUp(() {
      tools = DuskArtisanProvider().mcpTools();
    });

    // -------------------------------------------------------------------------
    // Length
    // -------------------------------------------------------------------------

    test('returns exactly 17 descriptors', () {
      expect(tools, hasLength(17));
    });

    // -------------------------------------------------------------------------
    // Names
    // -------------------------------------------------------------------------

    test('contains all 17 expected tool names', () {
      final names = tools.map((t) => t.name).toList();
      expect(
        names,
        containsAll(<String>[
          // Original 6.
          'dusk_snap',
          'dusk_tap',
          'dusk_screenshot',
          'dusk_hover',
          'dusk_drag',
          'dusk_type',
          // 10 from Wave 2.
          'dusk_scroll',
          'dusk_wait_for',
          'dusk_dismiss_modals',
          'dusk_navigate',
          'dusk_navigate_back',
          'dusk_get_routes',
          'dusk_press_key',
          'dusk_select_option',
          'dusk_evaluate',
          'dusk_close_app',
          // Step 16.
          'dusk_find',
        ]),
      );
    });

    test('dusk_find descriptor is present and maps to ext.dusk.find', () {
      final find = tools.firstWhere((t) => t.name == 'dusk_find');
      expect(find.extensionMethod, equals('ext.dusk.find'));
      // No top-level required keys — at-least-one validation lives in the
      // handler itself.
      expect(find.inputSchema.containsKey('required'), isFalse);
      final properties = find.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties.keys,
          containsAll(<String>['text', 'semanticsLabel', 'key']));
    });

    // -------------------------------------------------------------------------
    // Extension methods
    // -------------------------------------------------------------------------

    test('each descriptor maps to the correct ext.dusk.* extension method', () {
      final byName = {for (final t in tools) t.name: t.extensionMethod};

      // Original 6.
      expect(byName['dusk_snap'], equals('ext.dusk.snap'));
      expect(byName['dusk_tap'], equals('ext.dusk.tap'));
      expect(byName['dusk_screenshot'], equals('ext.dusk.screenshot'));
      expect(byName['dusk_hover'], equals('ext.dusk.hover'));
      expect(byName['dusk_drag'], equals('ext.dusk.drag'));
      expect(byName['dusk_type'], equals('ext.dusk.type'));
      // 10 new.
      expect(byName['dusk_scroll'], equals('ext.dusk.scroll'));
      expect(byName['dusk_wait_for'], equals('ext.dusk.wait_for'));
      expect(byName['dusk_dismiss_modals'], equals('ext.dusk.dismiss_modals'));
      expect(byName['dusk_navigate'], equals('ext.dusk.navigate'));
      expect(byName['dusk_navigate_back'], equals('ext.dusk.navigate_back'));
      expect(byName['dusk_get_routes'], equals('ext.dusk.get_routes'));
      expect(byName['dusk_press_key'], equals('ext.dusk.press_key'));
      expect(byName['dusk_select_option'], equals('ext.dusk.select_option'));
      expect(byName['dusk_evaluate'], equals('ext.dusk.evaluate'));
      expect(byName['dusk_close_app'], equals('ext.dusk.close_app'));
      // Step 16.
      expect(byName['dusk_find'], equals('ext.dusk.find'));
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
    // Description sanity — under 2KB cap (Claude Code truncates at 2KB chars)
    // -------------------------------------------------------------------------

    test('every description fits well under the 2KB Claude Code cap', () {
      for (final tool in tools) {
        expect(
          tool.description.length,
          lessThan(2048),
          reason: '${tool.name}.description is ${tool.description.length} '
              'chars (cap 2048)',
        );
      }
    });

    test('every description starts with an imperative verb sentence', () {
      // Sanity check: first non-empty line ends with a period and exists.
      for (final tool in tools) {
        final firstLine = tool.description.split('\n').first.trim();
        expect(
          firstLine,
          isNotEmpty,
          reason: '${tool.name}.description has empty first line',
        );
        expect(
          firstLine.endsWith('.'),
          isTrue,
          reason: '${tool.name}.description first line should end with `.`',
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

    test('dusk_scroll declares ref as required', () {
      final scroll = tools.firstWhere((t) => t.name == 'dusk_scroll');
      final required = scroll.inputSchema['required'] as List<dynamic>;
      expect(required, contains('ref'));
    });

    test('dusk_navigate declares route as required', () {
      final nav = tools.firstWhere((t) => t.name == 'dusk_navigate');
      final required = nav.inputSchema['required'] as List<dynamic>;
      expect(required, contains('route'));
    });

    test('dusk_press_key declares key as required', () {
      final press = tools.firstWhere((t) => t.name == 'dusk_press_key');
      final required = press.inputSchema['required'] as List<dynamic>;
      expect(required, contains('key'));
    });

    test('dusk_select_option declares ref and value as required', () {
      final sel = tools.firstWhere((t) => t.name == 'dusk_select_option');
      final required = sel.inputSchema['required'] as List<dynamic>;
      expect(required, containsAll(<String>['ref', 'value']));
    });

    test('dusk_evaluate declares expression as required', () {
      final eval = tools.firstWhere((t) => t.name == 'dusk_evaluate');
      final required = eval.inputSchema['required'] as List<dynamic>;
      expect(required, contains('expression'));
    });

    test('dusk_snap does not declare required params', () {
      final snap = tools.firstWhere((t) => t.name == 'dusk_snap');
      expect(snap.inputSchema.containsKey('required'), isFalse);
    });

    test('dusk_screenshot does not declare required params', () {
      final screenshot = tools.firstWhere((t) => t.name == 'dusk_screenshot');
      expect(screenshot.inputSchema.containsKey('required'), isFalse);
    });

    test('dusk_dismiss_modals does not declare required params', () {
      final dismiss = tools.firstWhere((t) => t.name == 'dusk_dismiss_modals');
      expect(dismiss.inputSchema.containsKey('required'), isFalse);
    });

    test('dusk_navigate_back does not declare required params', () {
      final back = tools.firstWhere((t) => t.name == 'dusk_navigate_back');
      expect(back.inputSchema.containsKey('required'), isFalse);
    });

    test('dusk_get_routes does not declare required params', () {
      final routes = tools.firstWhere((t) => t.name == 'dusk_get_routes');
      expect(routes.inputSchema.containsKey('required'), isFalse);
    });

    test('dusk_close_app does not declare required params', () {
      final close = tools.firstWhere((t) => t.name == 'dusk_close_app');
      expect(close.inputSchema.containsKey('required'), isFalse);
    });

    test('dusk_wait_for does not require any single condition (one-of)', () {
      // wait_for accepts one-of: text / textGone / expression — none singly
      // required at the schema level (validation happens in the handler).
      final wait = tools.firstWhere((t) => t.name == 'dusk_wait_for');
      expect(wait.inputSchema.containsKey('required'), isFalse);
    });
  });
}
