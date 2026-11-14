import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/tapir_dowel_provider.dart';

/// Verifies which commands offer `--json`, across the whole provider rather
/// than one command at a time.
///
/// The flag exists because the CLI used to split by verb: read commands
/// printed JSON, side-effect verbs printed a one-line summary, and an agent
/// driving from a shell had to know which shape each verb produced. `--json`
/// makes that a caller's choice, which is only true if EVERY summarising
/// verb carries it. A per-command test cannot catch the one that was
/// missed; this one can.
///
/// The commands that already print a JSON payload (or a file path) do not
/// take the flag, so the split is asserted in both directions.
void main() {
  /// Verbs that print a one-line human summary and therefore need the
  /// escape hatch to the full envelope.
  const Set<String> summarising = <String>{
    'tapir:snap',
    'tapir:tap',
    'tapir:hover',
    'tapir:drag',
    'tapir:double_click',
    'tapir:right_click',
    'tapir:triple_click',
    'tapir:type',
    'tapir:fill',
    'tapir:clear',
    'tapir:press_key',
    'tapir:focus',
    'tapir:blur',
    'tapir:scroll',
    'tapir:select_option',
    'tapir:set_checkbox',
    'tapir:navigate',
    'tapir:navigate_back',
    'tapir:close_app',
    'tapir:wait_for',
    'tapir:wait_for_network_idle',
    'tapir:perf_begin',
    'tapir:perf_end',
    'tapir:perf_insight',
    'tapir:perf_run',
    'tapir:perf_compare',
    'tapir:perf_campaign',
  };

  group('TapirDowelProvider --json surface', () {
    test('every summarising verb declares --json', () {
      final List<String> missing = <String>[];
      for (final DowelCommand command in TapirDowelProvider().commands()) {
        if (!summarising.contains(command.name)) continue;
        final ArgParser parser = ArgParser();
        command.configure(parser);
        if (!parser.options.containsKey('json')) missing.add(command.name);
      }

      expect(missing, isEmpty, reason: 'these verbs summarise with no way out');
    });

    test('--json defaults to off so a terminal still reads a sentence', () {
      for (final DowelCommand command in TapirDowelProvider().commands()) {
        if (!summarising.contains(command.name)) continue;
        final ArgParser parser = ArgParser();
        command.configure(parser);
        expect(
          parser.options['json']!.defaultsTo,
          isFalse,
          reason: '${command.name} would change its default output shape',
        );
      }
    });

    test('a command that already prints JSON does not take the flag', () {
      // Adding it there would imply the default is something else, which
      // is the confusion the flag exists to remove.
      final Map<String, bool> declared = <String, bool>{};
      for (final DowelCommand command in TapirDowelProvider().commands()) {
        final ArgParser parser = ArgParser();
        command.configure(parser);
        declared[command.name] = parser.options.containsKey('json');
      }

      expect(declared['tapir:find'], isFalse);
      expect(declared['tapir:observe'], isFalse);
      expect(declared['tapir:exceptions'], isFalse);
      expect(declared['tapir:screenshot'], isFalse);
      // Prints only the path of the file it wrote.
      expect(declared['tapir:perf_trace'], isFalse);
    });

    test('the summarising set covers every verb that declares the flag', () {
      // Catches the reverse drift: a new verb that adds --json without
      // being listed here would otherwise never be asserted on.
      final List<String> unlisted = <String>[];
      for (final DowelCommand command in TapirDowelProvider().commands()) {
        final ArgParser parser = ArgParser();
        command.configure(parser);
        if (parser.options.containsKey('json') &&
            !summarising.contains(command.name)) {
          unlisted.add(command.name);
        }
      }

      expect(unlisted, isEmpty);
    });
  });
}
