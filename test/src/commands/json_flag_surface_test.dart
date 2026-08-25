import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_artisan_provider.dart';

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
    'dusk:tap',
    'dusk:hover',
    'dusk:drag',
    'dusk:dblclick',
    'dusk:right_click',
    'dusk:triple_click',
    'dusk:type',
    'dusk:fill',
    'dusk:clear',
    'dusk:press_key',
    'dusk:focus',
    'dusk:blur',
    'dusk:scroll',
    'dusk:select_option',
    'dusk:set_checkbox',
    'dusk:navigate',
    'dusk:navigate_back',
    'dusk:close_app',
    'dusk:wait',
    'dusk:wait_for_network_idle',
    'dusk:perf_begin',
    'dusk:perf_end',
  };

  group('DuskArtisanProvider --json surface', () {
    test('every summarising verb declares --json', () {
      final List<String> missing = <String>[];
      for (final ArtisanCommand command in DuskArtisanProvider().commands()) {
        if (!summarising.contains(command.name)) continue;
        final ArgParser parser = ArgParser();
        command.configure(parser);
        if (!parser.options.containsKey('json')) missing.add(command.name);
      }

      expect(missing, isEmpty, reason: 'these verbs summarise with no way out');
    });

    test('--json defaults to off so a terminal still reads a sentence', () {
      for (final ArtisanCommand command in DuskArtisanProvider().commands()) {
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
      for (final ArtisanCommand command in DuskArtisanProvider().commands()) {
        final ArgParser parser = ArgParser();
        command.configure(parser);
        declared[command.name] = parser.options.containsKey('json');
      }

      expect(declared['dusk:snap'], isFalse);
      expect(declared['dusk:find'], isFalse);
      expect(declared['dusk:observe'], isFalse);
      expect(declared['dusk:exceptions'], isFalse);
      expect(declared['dusk:screenshot'], isFalse);
    });

    test('the summarising set covers every verb that declares the flag', () {
      // Catches the reverse drift: a new verb that adds --json without
      // being listed here would otherwise never be asserted on.
      final List<String> unlisted = <String>[];
      for (final ArtisanCommand command in DuskArtisanProvider().commands()) {
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
