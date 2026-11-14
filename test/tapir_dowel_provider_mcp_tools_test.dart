import 'dart:convert';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/tapir_dowel_provider.dart';

void main() {
  group('TapirDowelProvider.commands()', () {
    late List<DowelCommand> cmds;

    setUp(() {
      cmds = TapirDowelProvider().commands();
    });

    test('returns exactly 42 commands', () {
      expect(cmds, hasLength(42));
    });

    test('registers tapir:run as a connected command', () {
      final run = cmds.firstWhere((c) => c.name == 'tapir:run');
      expect(run.runtimeType.toString(), 'TapirRunCommand');
      expect(run.boot, CommandBoot.connected);
    });

    test('contains every shipped command', () {
      final names = cmds.map((c) => c.runtimeType.toString()).toSet();
      expect(
        names,
        containsAll(<String>[
          // Snapshot, tap, screenshot.
          'TapirSnapCommand',
          'TapirTapCommand',
          'TapirScreenshotCommand',
          // Installer.
          'TapirInstallCommand',
          // Type, scroll, wait, hover, drag, modal.
          'TapirTypeCommand',
          'TapirScrollCommand',
          'TapirWaitForCommand',
          'TapirHoverCommand',
          'TapirDragCommand',
          'TapirDismissModalsCommand',
          // Diagnostics.
          'TapirDoctorCommand',
          // CLI/MCP symmetry pass.
          'TapirNavigateCommand',
          'TapirNavigateBackCommand',
          'TapirGetRoutesCommand',
          'TapirPressKeyCommand',
          'TapirSelectOptionCommand',
          'TapirCloseAppCommand',
          'TapirFindCommand',
          // Step 3.4.
          'TapirWaitForNetworkIdleCommand',
          // Step 3.5.
          'TapirConsoleCommand',
          'TapirExceptionsCommand',
          'TapirDoubleClickCommand',
          'TapirSetCheckboxCommand',
          // Step 4.1.
          'TapirObserveCommand',
          // Step 4.2.
          'TapirHotReloadAndSnapCommand',
          // D7: harness workarounds promoted to first-class commands.
          'TapirFillCommand',
          'TapirResetOverlaysCommand',
          // Perf session pair.
          'TapirPerfBeginCommand',
          'TapirPerfEndCommand',
          'TapirPerfInsightCommand',
          // Perf runner, compare and trace export.
          'TapirPerfRunCommand',
          'TapirPerfCompareCommand',
          'TapirPerfTraceCommand',
          // Perf campaign.
          'TapirPerfCampaignCommand',
        ]),
      );
    });
  });

  group('TapirDowelProvider.mcpTools()', () {
    late List<McpToolDescriptor> tools;

    setUp(() {
      tools = TapirDowelProvider().mcpTools();
    });

    // -------------------------------------------------------------------------
    // Length
    // -------------------------------------------------------------------------

    test('returns exactly 40 descriptors', () {
      expect(tools, hasLength(40));
    });

    // -------------------------------------------------------------------------
    // Names
    // -------------------------------------------------------------------------

    test('contains all 30 expected tool names', () {
      final names = tools.map((t) => t.name).toList();
      expect(
        names,
        containsAll(<String>[
          // Original 6.
          'tapir_snap',
          'tapir_tap',
          'tapir_screenshot',
          'tapir_hover',
          'tapir_drag',
          'tapir_type',
          // 10 from Wave 2.
          'tapir_scroll',
          'tapir_wait_for',
          'tapir_dismiss_modals',
          'tapir_navigate',
          'tapir_navigate_back',
          'tapir_get_routes',
          'tapir_press_key',
          'tapir_select_option',
          'tapir_evaluate',
          'tapir_close_app',
          // Step 16.
          'tapir_find',
          // Step 3.4.
          'tapir_wait_for_network_idle',
          // Step 3.5.
          'tapir_console',
          'tapir_exceptions',
          'tapir_double_click',
          'tapir_set_checkbox',
          // Step 4.1.
          'tapir_observe',
          // Step 4.2.
          'tapir_hot_reload_and_snap',
          // Wave 4 CDP tools.
          'tapir_resize_viewport',
          'tapir_device_profile',
          // D7: harness workarounds promoted to first-class tools.
          'tapir_fill',
          'tapir_reset_overlays',
          // Perf session pair.
          'tapir_perf_begin',
          'tapir_perf_end',
          'tapir_perf_insight',
          'tapir_perf_run',
          'tapir_perf_compare',
          'tapir_perf_trace',
          'tapir_run',
        ]),
      );
    });

    test('tapir_find descriptor is present and maps to ext.tapir.find', () {
      final find = tools.firstWhere((t) => t.name == 'tapir_find');
      expect(find.extensionMethod, equals('ext.tapir.find'));
      // No top-level required keys — at-least-one validation lives in the
      // handler itself.
      expect(find.inputSchema.containsKey('required'), isFalse);
      final properties = find.inputSchema['properties'] as Map<String, dynamic>;
      expect(
        properties.keys,
        containsAll(<String>['text', 'semanticsLabel', 'key']),
      );
    });

    // -------------------------------------------------------------------------
    // Extension methods
    // -------------------------------------------------------------------------

    test(
      'each descriptor maps to the correct ext.tapir.* extension method',
      () {
        final byName = {for (final t in tools) t.name: t.extensionMethod};

        // Original 6.
        expect(byName['tapir_snap'], equals('ext.tapir.snap'));
        expect(byName['tapir_tap'], equals('ext.tapir.tap'));
        expect(byName['tapir_screenshot'], equals('ext.tapir.screenshot'));
        expect(byName['tapir_hover'], equals('ext.tapir.hover'));
        expect(byName['tapir_drag'], equals('ext.tapir.drag'));
        expect(byName['tapir_type'], equals('ext.tapir.type'));
        // 10 new.
        expect(byName['tapir_scroll'], equals('ext.tapir.scroll'));
        expect(byName['tapir_wait_for'], equals('ext.tapir.wait_for'));
        expect(
          byName['tapir_dismiss_modals'],
          equals('ext.tapir.dismiss_modals'),
        );
        expect(byName['tapir_navigate'], equals('ext.tapir.navigate'));
        expect(
          byName['tapir_navigate_back'],
          equals('ext.tapir.navigate_back'),
        );
        expect(byName['tapir_get_routes'], equals('ext.tapir.get_routes'));
        expect(byName['tapir_press_key'], equals('ext.tapir.press_key'));
        expect(
          byName['tapir_select_option'],
          equals('ext.tapir.select_option'),
        );
        expect(byName['tapir_evaluate'], equals('ext.tapir.evaluate'));
        expect(byName['tapir_close_app'], equals('ext.tapir.close_app'));
        // Step 16.
        expect(byName['tapir_find'], equals('ext.tapir.find'));
        // Step 3.4.
        expect(
          byName['tapir_wait_for_network_idle'],
          equals('ext.tapir.wait_for_network_idle'),
        );
        // Step 3.5.
        expect(byName['tapir_console'], equals('ext.tapir.console'));
        expect(byName['tapir_exceptions'], equals('ext.tapir.exceptions'));
        expect(byName['tapir_double_click'], equals('ext.tapir.double_click'));
        expect(byName['tapir_set_checkbox'], equals('ext.tapir.set_checkbox'));
        // Step 4.1.
        expect(byName['tapir_observe'], equals('ext.tapir.observe'));
        // Step 4.2. NO VM extension surface: hot reload cannot fire from
        // inside the running isolate. The descriptor routes through the
        // `dowel:` dispatch prefix so the MCP server runs the CLI command
        // in-process instead of calling a VM Service extension.
        expect(
          byName['tapir_hot_reload_and_snap'],
          equals('dowel:tapir:hot_reload_and_snap'),
        );
        // Wave 4 CDP tools. Both route via dowel: dispatch prefix to CLI
        // commands instead of VM Service extensions (CDP is orchestrator-side,
        // not inside the running Flutter app).
        expect(
          byName['tapir_resize_viewport'],
          equals('dowel:tapir:resize_viewport'),
        );
        expect(
          byName['tapir_device_profile'],
          equals('dowel:tapir:device_profile'),
        );
        // D7.
        expect(byName['tapir_fill'], equals('ext.tapir.fill'));
        expect(
          byName['tapir_reset_overlays'],
          equals('ext.tapir.reset_overlays'),
        );
        // Perf session pair.
        expect(byName['tapir_perf_begin'], equals('ext.tapir.perf_begin'));
        expect(byName['tapir_perf_end'], equals('ext.tapir.perf_end'));
        expect(byName['tapir_perf_insight'], equals('ext.tapir.perf_insight'));
        // Host-side: the run, the compare and the file write happen in the
        // MCP server's process, so all three route through the substrate.
        expect(byName['tapir_perf_run'], equals('dowel:tapir:perf_run'));
        expect(
          byName['tapir_perf_compare'],
          equals('dowel:tapir:perf_compare'),
        );
        expect(byName['tapir_perf_trace'], equals('dowel:tapir:perf_trace'));
        // The batch runs every step's command in the MCP server's process on
        // its one VM Service connection.
        expect(byName['tapir_run'], equals('dowel:tapir:run'));
      },
    );

    test('tapir_run requires a steps string array and takes continue', () {
      final run = tools.firstWhere((t) => t.name == 'tapir_run');
      expect(run.inputSchema['required'], <String>['steps']);
      final properties = run.inputSchema['properties'] as Map<String, dynamic>;
      final steps = properties['steps'] as Map<String, dynamic>;
      expect(steps['type'], 'array');
      expect((steps['items'] as Map<String, dynamic>)['type'], 'string');
      expect(
        (properties['continue'] as Map<String, dynamic>)['type'],
        'boolean',
      );
    });

    test('tapir_perf_run requires scenario and names every option', () {
      final run = tools.firstWhere((t) => t.name == 'tapir_perf_run');
      expect(run.inputSchema['required'], <String>['scenario']);
      final properties = run.inputSchema['properties'] as Map<String, dynamic>;
      expect(
        properties.keys,
        containsAll(<String>[
          'scenario',
          'variant',
          'label',
          'out',
          'repeat',
          'platform',
          'timing',
          'against',
          'semantics-pass',
          'json',
        ]),
      );
      // Every file with `variants` needs one picked; the tool's arguments
      // reach tapir:perf_run's MapInput under the same key.
      expect((properties['variant'] as Map<String, dynamic>)['type'], 'string');
    });

    test('tapir_perf_compare requires a and b', () {
      final compare = tools.firstWhere((t) => t.name == 'tapir_perf_compare');
      expect(compare.inputSchema['required'], <String>['a', 'b']);
    });

    test('tapir_perf_trace requires out and takes an optional token', () {
      final trace = tools.firstWhere((t) => t.name == 'tapir_perf_trace');
      expect(trace.inputSchema['required'], <String>['out']);
      final properties =
          trace.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties.keys, containsAll(<String>['out', 'token']));
    });

    test('tapir_perf_begin declares mode as an attribution|timing enum', () {
      final begin = tools.firstWhere((t) => t.name == 'tapir_perf_begin');
      final properties =
          begin.inputSchema['properties'] as Map<String, dynamic>;
      expect((properties['mode'] as Map<String, dynamic>)['enum'], <String>[
        'attribution',
        'timing',
      ]);
    });

    test('tapir_perf_insight requires id and takes an optional token', () {
      final insight = tools.firstWhere((t) => t.name == 'tapir_perf_insight');
      expect(insight.inputSchema['required'], <String>['id']);
      final properties =
          insight.inputSchema['properties'] as Map<String, dynamic>;
      expect(properties.keys, containsAll(<String>['id', 'token']));
    });

    test('tapir_perf_begin declares the phases flag and requires nothing', () {
      final begin = tools.firstWhere((t) => t.name == 'tapir_perf_begin');
      expect(begin.inputSchema.containsKey('required'), isFalse);
      final properties =
          begin.inputSchema['properties'] as Map<String, dynamic>;
      // Step 11 drives the session by this exact param name; a rename here
      // breaks the driven run with no compile error anywhere.
      expect(properties.keys, contains('phases'));
      expect(
        (properties['phases'] as Map<String, dynamic>)['type'],
        equals('boolean'),
      );
    });

    test('tapir_perf_end does not declare required params', () {
      final end = tools.firstWhere((t) => t.name == 'tapir_perf_end');
      expect(end.inputSchema.containsKey('required'), isFalse);
    });

    test('tapir_fill declares ref and text as required', () {
      final fill = tools.firstWhere((t) => t.name == 'tapir_fill');
      final required = fill.inputSchema['required'] as List<dynamic>;
      expect(required, containsAll(<String>['ref', 'text']));
    });

    test(
      'tapir_tap, tapir_fill and tapir_navigate take a snapshot mode enum',
      () {
        for (final String name in <String>[
          'tapir_tap',
          'tapir_fill',
          'tapir_navigate',
        ]) {
          final tool = tools.firstWhere((t) => t.name == name);
          final properties = tool.inputSchema['properties'] as Map;
          final snapshot = properties['snapshot'] as Map?;
          expect(snapshot, isNotNull, reason: '$name has no snapshot property');
          expect(snapshot!['type'], 'string');
          expect(snapshot['enum'], <String>['full', 'diff', 'none']);
          expect(
            tool.description,
            contains('`snapshot: "diff"`'),
            reason: name,
          );
        }
      },
    );

    test('tapir_reset_overlays does not declare required params', () {
      final reset = tools.firstWhere((t) => t.name == 'tapir_reset_overlays');
      expect(reset.inputSchema.containsKey('required'), isFalse);
    });

    test('the CDP emulation tools say the override lasts only for the call\'s '
        'session', () {
      // Chrome drops an Emulation.* override when the DevTools session that
      // sent it detaches, and each call opens and closes its own session.
      final resize = tools.firstWhere((t) => t.name == 'tapir_resize_viewport');
      final device = tools.firstWhere((t) => t.name == 'tapir_device_profile');
      for (final tool in <McpToolDescriptor>[resize, device]) {
        expect(tool.description, contains('only as long as'));
        expect(tool.description, contains('CDP session'));
      }
      expect(resize.description, contains('--hold'));
    });

    test(
      'no two descriptors share an extensionMethod (no overlap, no gap)',
      () {
        final methods = tools.map((t) => t.extensionMethod).toList();
        expect(methods.toSet(), hasLength(tools.length));
      },
    );

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
          reason:
              '${tool.name}.description is ${tool.description.length} '
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

    test('tapir_tap declares ref as required', () {
      final tap = tools.firstWhere((t) => t.name == 'tapir_tap');
      final required = tap.inputSchema['required'] as List<dynamic>;
      expect(required, contains('ref'));
    });

    test('tapir_hover declares ref as required', () {
      final hover = tools.firstWhere((t) => t.name == 'tapir_hover');
      final required = hover.inputSchema['required'] as List<dynamic>;
      expect(required, contains('ref'));
    });

    test('tapir_drag declares startRef and endRef as required', () {
      final drag = tools.firstWhere((t) => t.name == 'tapir_drag');
      final required = drag.inputSchema['required'] as List<dynamic>;
      expect(required, containsAll(<String>['startRef', 'endRef']));
    });

    test('tapir_type declares ref and text as required', () {
      final type = tools.firstWhere((t) => t.name == 'tapir_type');
      final required = type.inputSchema['required'] as List<dynamic>;
      expect(required, containsAll(<String>['ref', 'text']));
    });

    test('tapir_navigate declares route as required', () {
      final nav = tools.firstWhere((t) => t.name == 'tapir_navigate');
      final required = nav.inputSchema['required'] as List<dynamic>;
      expect(required, contains('route'));
    });

    test('tapir_press_key declares key as required', () {
      final press = tools.firstWhere((t) => t.name == 'tapir_press_key');
      final required = press.inputSchema['required'] as List<dynamic>;
      expect(required, contains('key'));
    });

    test('tapir_select_option declares ref and value as required', () {
      final sel = tools.firstWhere((t) => t.name == 'tapir_select_option');
      final required = sel.inputSchema['required'] as List<dynamic>;
      expect(required, containsAll(<String>['ref', 'value']));
    });

    test('tapir_evaluate declares expression as required', () {
      final eval = tools.firstWhere((t) => t.name == 'tapir_evaluate');
      final required = eval.inputSchema['required'] as List<dynamic>;
      expect(required, contains('expression'));
    });

    test('tapir_snap does not declare required params', () {
      final snap = tools.firstWhere((t) => t.name == 'tapir_snap');
      expect(snap.inputSchema.containsKey('required'), isFalse);
    });

    test('tapir_screenshot does not declare required params', () {
      final screenshot = tools.firstWhere((t) => t.name == 'tapir_screenshot');
      expect(screenshot.inputSchema.containsKey('required'), isFalse);
    });

    test('tapir_dismiss_modals does not declare required params', () {
      final dismiss = tools.firstWhere((t) => t.name == 'tapir_dismiss_modals');
      expect(dismiss.inputSchema.containsKey('required'), isFalse);
    });

    test('tapir_navigate_back does not declare required params', () {
      final back = tools.firstWhere((t) => t.name == 'tapir_navigate_back');
      expect(back.inputSchema.containsKey('required'), isFalse);
    });

    test('tapir_get_routes does not declare required params', () {
      final routes = tools.firstWhere((t) => t.name == 'tapir_get_routes');
      expect(routes.inputSchema.containsKey('required'), isFalse);
    });

    test('tapir_close_app does not declare required params', () {
      final close = tools.firstWhere((t) => t.name == 'tapir_close_app');
      expect(close.inputSchema.containsKey('required'), isFalse);
    });

    test('tapir_wait_for does not require any single condition (one-of)', () {
      // wait_for accepts one-of: text / textGone / expression — none singly
      // required at the schema level (validation happens in the handler).
      final wait = tools.firstWhere((t) => t.name == 'tapir_wait_for');
      expect(wait.inputSchema.containsKey('required'), isFalse);
    });

    test('tapir_resize_viewport can be called with only reset', () {
      final resize = tools.firstWhere((t) => t.name == 'tapir_resize_viewport');
      final properties =
          resize.inputSchema['properties'] as Map<String, dynamic>;

      // The description's own example is `{"reset": true}`; a `required`
      // width and height made dowel's validator refuse it. The command
      // refuses a resize that names no size instead.
      expect(resize.inputSchema['required'], isNull);
      expect(properties.keys, contains('reset'));
    });

    test('tapir_resize_viewport names the pixel ratio the command reads', () {
      final resize = tools.firstWhere((t) => t.name == 'tapir_resize_viewport');
      final properties =
          resize.inputSchema['properties'] as Map<String, dynamic>;

      // MCP arguments reach TapirResizeViewportCommand under their own names, and it
      // reads `dpr`. The schema used to say `deviceScaleFactor`, which was
      // accepted and then ignored.
      expect(properties.keys, contains('dpr'));
      expect(properties.keys, isNot(contains('deviceScaleFactor')));
      expect(resize.description, isNot(contains('deviceScaleFactor')));
    });

    test('tapir_device_profile does not declare required params', () {
      final device = tools.firstWhere((t) => t.name == 'tapir_device_profile');
      expect(device.inputSchema.containsKey('required'), isFalse);
    });

    test('every schema is closed: a key it does not list is refused', () {
      // dowel wraps each schema in a dart_mcp ObjectSchema that validates
      // call arguments, so an open schema lets a typo through to a handler
      // that ignores it and answers with a clean response.
      for (final tool in tools) {
        expect(
          tool.inputSchema['additionalProperties'],
          isFalse,
          reason: '${tool.name} must declare additionalProperties: false',
        );
      }
    });

    test('a closed schema still lists the knobs its handler reads', () {
      // Closing a schema refuses every key it does not list, so each knob an
      // agent is meant to pass has to be listed. The coordinate keys (x, y,
      // toX, toY, drag dx/dy), reportPoint, perf_end's full and screenshot's
      // geometry, and tapir:resize_viewport's hold, stay out on purpose: the perf
      // runner and the CLI call the extensions directly, and they are not MCP
      // surface.
      const snapshot = ['snapshot', 'includeSnapshot'];
      const gate = ['checkStable', 'checkReceivesEvents'];
      final expected = <String, List<String>>{
        'tapir_snap': ['includeEnrichers'],
        'tapir_tap': ['includeSnapshot', ...gate],
        'tapir_hover': [...snapshot, ...gate],
        'tapir_drag': [...snapshot, ...gate],
        'tapir_type': [...snapshot, ...gate],
        'tapir_double_click': [...snapshot, ...gate],
        'tapir_right_click': ['snapshot'],
        'tapir_triple_click': ['snapshot'],
        'tapir_fill': gate,
        'tapir_navigate': ['includeSnapshot'],
        'tapir_navigate_back': snapshot,
        'tapir_press_key': snapshot,
        'tapir_find': ['contains'],
      };

      expected.forEach((name, keys) {
        final tool = tools.firstWhere((t) => t.name == name);
        final properties =
            tool.inputSchema['properties'] as Map<String, dynamic>;

        expect(properties.keys, containsAll(keys), reason: name);
      });
    });

    test('the snapshot knob is the same enum on every verb that has it', () {
      for (final tool in tools) {
        final properties =
            tool.inputSchema['properties'] as Map<String, dynamic>;
        final snapshot = properties['snapshot'] as Map<String, dynamic>?;
        if (snapshot == null) continue;

        expect(snapshot['enum'], ['full', 'diff', 'none'], reason: tool.name);
      }
    });

    test('tapir_scroll lists every key the extension reads', () {
      final scroll = tools.firstWhere((t) => t.name == 'tapir_scroll');
      final properties =
          scroll.inputSchema['properties'] as Map<String, dynamic>;

      // ext_scroll.dart reads these eight; the schema used to list only the
      // direction and pixels pair, which the extension then ignored.
      expect(
        properties.keys,
        containsAll(<String>[
          'ref',
          'direction',
          'pixels',
          'dx',
          'dy',
          'intoView',
          'includeSnapshot',
          'snapshot',
        ]),
      );
    });

    test('tapir_scroll does not require a ref: the handler walks the root', () {
      final scroll = tools.firstWhere((t) => t.name == 'tapir_scroll');

      // ext_scroll.dart falls back to the first Scrollable when no ref is
      // given; tapir:scroll (the CLI) is the one that insists on --ref.
      expect(scroll.inputSchema['required'], isNull);
    });

    test('tapir_wait_for describes a timeout as a result, not an error', () {
      final wait = tools.firstWhere((t) => t.name == 'tapir_wait_for');
      final properties = wait.inputSchema['properties'] as Map<String, dynamic>;

      // ext_wait_find.dart answers a timeout with `{matched: false, reason:
      // 'timeout'}` as a success, and picks the first of several one-of keys.
      expect(wait.description, contains('matched: false'));
      expect(wait.description, isNot(contains('returns an error result')));
      expect(wait.description, isNot(contains('multiple are passed')));
      for (final key in <String>['text', 'textGone']) {
        final description =
            (properties[key] as Map<String, dynamic>)['description'] as String;
        expect(description, contains('Text'), reason: key);
        expect(description, isNot(contains('Semantics node')), reason: key);
      }
    });

    test('the click variants say their snapshot default is true', () {
      for (final name in <String>['tapir_right_click', 'tapir_triple_click']) {
        final tool = tools.firstWhere((t) => t.name == name);
        final properties =
            tool.inputSchema['properties'] as Map<String, dynamic>;
        final snapshot = properties['includeSnapshot'] as Map<String, dynamic>;

        expect(snapshot['description'], contains('default true'), reason: name);
        expect(tool.description, contains('includeSnapshot` (default true)'));
      }
    });
  });
}
