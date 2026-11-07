import 'package:fluttersdk_artisan/artisan.dart';

/// `artisan dusk:run "tap --ref=e5" "snap --grep Counter"`: run several dusk
/// verbs against the running app in one call.
///
/// Each step is a verb line, tokenised shell-style (single and double quotes,
/// backslash escapes) and parsed by the verb's own [ArtisanCommand.configure],
/// so a step accepts exactly what the standalone command accepts. Every step
/// runs on this call's VM Service connection with its output captured; the
/// caller sees one line per step, then the last step's output.
///
/// The batch stops at the first step that exits non-zero and exits with that
/// step's code. `--continue` runs every step and exits with the first
/// non-zero code, or 0. A step naming `dusk:run` itself, an unknown verb, or a
/// verb that does not boot connected (`dusk:resize`, `dusk:device`,
/// `dusk:install`, `dusk:doctor`, `dusk:perf_campaign`, `dusk:perf_compare`)
/// fails as that step with exit 1. A step that ends the app (`dusk:close_app`,
/// `dusk:perf_run`) is accepted, but later steps then find no connection.
///
/// The MCP tool passes the steps as a `steps` list; the CLI passes them as
/// positional arguments.
final class DuskRunCommand extends ArtisanCommand {
  /// Longest step output kept on the step line; the rest stays out of the
  /// agent's context.
  static const int _digestLength = 120;

  @override
  String get name => 'dusk:run';

  @override
  String get description => 'Run several dusk verbs in one call, e.g. '
      'dusk:run "tap --ref=e5" "snap --grep Counter".';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addFlag(
      'continue',
      negatable: false,
      help: 'Run every step even after one fails; exit with the first '
          'non-zero code.',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Collect the steps from whichever surface called.
    final List<String> steps = _steps(ctx.input);
    if (steps.isEmpty) {
      ctx.output.error(
        'No steps given. Pass each step as a quoted verb line, e.g. '
        'dusk:run "tap --ref=e5" "snap".',
      );
      return 1;
    }
    final bool keepGoing = ctx.input.option('continue') == true;

    // 2. Run the steps in order, one summary line each.
    (int, int)? firstFailure;
    String lastOutput = '';
    for (int i = 0; i < steps.length; i++) {
      final String step = steps[i];
      final BufferedOutput captured = BufferedOutput(
        verbosity: ctx.output.verbosity,
      );
      final int code = await _runStep(ctx, step, captured);
      final String text = captured.content.trimRight();
      final String prefix = '[${i + 1}/${steps.length}] $step';
      if (code == 0) {
        // The last step's output is printed in full below, so its summary
        // line would only repeat the first line of it.
        final bool isLast = i == steps.length - 1;
        ctx.output.writeln('$prefix ok${isLast ? '' : _digest(text)}');
        lastOutput = text;
        continue;
      }
      ctx.output.writeln('$prefix failed (exit $code)');
      if (text.isNotEmpty) ctx.output.writeln(text);
      lastOutput = '';
      firstFailure ??= (i, code);
      if (!keepGoing) break;
    }

    // 3. The last step's output is the state the caller acts on next.
    if (lastOutput.isNotEmpty) ctx.output.writeln(lastOutput);
    if (firstFailure == null) return 0;
    final (int index, int code) = firstFailure;
    ctx.output.error('step ${index + 1} failed (exit $code): ${steps[index]}');
    return code;
  }

  /// Reads the steps from an MCP `steps` list, else the CLI positionals.
  List<String> _steps(ArtisanInput input) {
    final Object? listed = input.option('steps');
    if (listed is List) {
      return <String>[
        for (final Object? step in listed) '$step',
      ];
    }
    final List<String> positional = <String>[];
    for (String? step = input.argument(0);
        step != null;
        step = input.argument(positional.length)) {
      positional.add(step);
    }
    return positional;
  }

  /// Runs one verb line and answers its exit code; never throws for a step
  /// the caller got wrong or the app refused.
  Future<int> _runStep(
    ArtisanContext ctx,
    String step,
    BufferedOutput output,
  ) async {
    // 1. Split the line the way a shell would.
    final List<String> tokens;
    try {
      tokens = _tokenize(step);
    } on FormatException catch (e) {
      output.error(e.message);
      return 1;
    }
    if (tokens.isEmpty) {
      output.error('empty step');
      return 1;
    }

    // 2. Resolve the verb; a bare `tap` means `dusk:tap`.
    final String verb =
        tokens.first.contains(':') ? tokens.first : 'dusk:${tokens.first}';
    if (verb == name) {
      output.error('dusk:run cannot be nested inside a dusk:run step');
      return 1;
    }
    final ArtisanCommand? command = ctx.registry?.find(verb);
    if (command == null) {
      output.error('unknown verb $verb');
      return 1;
    }
    if (command.boot != CommandBoot.connected) {
      output.error(
        '$verb does not run on the connected app, so it cannot be a '
        'dusk:run step; call it on its own',
      );
      return 1;
    }

    // 3. Parse with the verb's own parser: ArgvInput reads its own results.
    final ArgParser parser = ArgParser();
    command.configure(parser);
    final ArgvInput input;
    try {
      input = ArgvInput(
        parser.parse(tokens.sublist(1)),
        signature: command.parsedSignature,
      );
    } on FormatException catch (e) {
      output.error('$verb: ${e.message}');
      return 1;
    }

    // 4. Run on this call's connection. The dispatcher maps these two only
    //    for the top-level command, so a step maps them itself.
    try {
      return await command.handle(
        ArtisanContext.connected(
          input,
          output,
          ctx.vmClient!,
          registry: ctx.registry,
        ),
      );
    } on ExtensionNotRegisteredException catch (e) {
      output.error(e.message);
      return ArtisanCommand.exitTryAgain;
    } catch (e) {
      // Not only Exception: argparse reports a missing `mandatory` option as
      // an ArgumentError, and one verb's failure must stay its own step's
      // failure (artisan's dispatcher maps any throw to exit 3 the same way).
      output.error('$verb failed: $e');
      return 3;
    }
  }

  /// A step line's first non-empty output line, shortened for the summary.
  String _digest(String text) {
    final String line = text
        .split('\n')
        .map((String l) => l.trim())
        .firstWhere((String l) => l.isNotEmpty, orElse: () => '');
    if (line.isEmpty) return '';
    if (line.length <= _digestLength) return ': $line';
    return ': ${line.substring(0, _digestLength)}...';
  }
}

/// Splits a step line into argv tokens the way a POSIX shell would.
///
/// Whitespace separates tokens; single quotes keep everything literal; double
/// quotes keep whitespace and honour `\"` and `\\`; a backslash outside
/// quotes escapes the next character. `""` is an empty token. Throws
/// [FormatException] on an unterminated quote or a trailing backslash.
List<String> _tokenize(String line) {
  final List<String> tokens = <String>[];
  final StringBuffer current = StringBuffer();
  bool inToken = false;
  String? quote;
  for (int i = 0; i < line.length; i++) {
    final String char = line[i];
    if (quote == "'") {
      if (char == "'") {
        quote = null;
      } else {
        current.write(char);
      }
      continue;
    }
    if (char == r'\') {
      if (i + 1 == line.length) {
        throw FormatException('trailing backslash in step: $line');
      }
      final String next = line[i + 1];
      if (quote == '"' && next != '"' && next != r'\') {
        current.write(char);
      } else {
        current.write(next);
        i++;
      }
      inToken = true;
      continue;
    }
    if (quote == '"') {
      if (char == '"') {
        quote = null;
      } else {
        current.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      inToken = true;
      continue;
    }
    if (char.trim().isEmpty) {
      if (inToken) {
        tokens.add(current.toString());
        current.clear();
        inToken = false;
      }
      continue;
    }
    current.write(char);
    inToken = true;
  }
  if (quote != null) {
    throw FormatException('unterminated quote in step: $line');
  }
  if (inToken) tokens.add(current.toString());
  return tokens;
}
