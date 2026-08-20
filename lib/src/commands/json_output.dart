import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

/// Declares the `--json` flag every `dusk:*` command accepts.
///
/// The CLI used to split by verb: read commands printed JSON, the
/// side-effect verbs printed a one-line summary, and a few printed a human
/// sentence for a payload that had structure worth reading. An agent driving
/// from a shell had to know which shape each verb produced, and the ones
/// that summarised dropped fields that mattered.
///
/// `--json` makes that a caller's choice rather than a property of the verb.
/// The default is unchanged, so a human reading a terminal still gets the
/// summary.
void addJsonFlag(ArgParser parser) {
  parser.addFlag(
    'json',
    help: 'Print the raw JSON envelope instead of the one-line summary.',
    defaultsTo: false,
  );
}

/// True when the caller asked for the JSON envelope.
bool wantsJson(ArtisanContext ctx) =>
    (ctx.input.option('json') as bool?) ?? false;

/// Prints [response] as JSON when `--json` is set, and calls [summary]
/// otherwise.
///
/// [summary] is a callback rather than a string so a command never pays to
/// build a sentence the caller is not going to read.
void emitEnvelope(
  ArtisanContext ctx,
  Map<String, dynamic> response,
  void Function() summary,
) {
  if (wantsJson(ctx)) {
    ctx.output.writeln(jsonEncode(response));
    return;
  }
  summary();
}
