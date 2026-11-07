import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';
import 'web_visibility.dart';

/// `artisan dusk:type --ref=<eN> --text=<string>` — type text into a focused widget.
class DuskTypeCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:type';

  @override
  String get description => 'Type text into a focused widget by ref token.';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser.addOption('ref',
        help: 'Snapshot ref token (e.g. e1).', mandatory: true);
    parser.addOption('text',
        help: 'Text to type into the focused widget.', mandatory: true);
    parser.addFlag('includeSnapshot',
        help: 'Embed the post-type snapshot in the response.',
        defaultsTo: false);
    parser.addOption(
      'snapshot',
      allowed: <String>['full', 'diff', 'none'],
      help: 'Print the post-type snapshot after the summary: the whole tree, '
          'only the lines changed since the last snapshot, or nothing. '
          'Overrides --includeSnapshot.',
    );
    parser.addFlag('checkStable',
        help: 'Run the Stable actionability gate.', defaultsTo: true);
    parser.addFlag('checkReceivesEvents',
        help: 'Run the Receives-Events actionability gate.', defaultsTo: true);
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output
          .error('Missing --ref=<eN>. Run dusk:snap first to obtain refs.');
      return 1;
    }
    final text = ctx.input.option('text') as String?;
    if (text == null) {
      ctx.output.error('Missing --text=<string>. Provide the text to type.');
      return 1;
    }
    final snapshotMode = ctx.input.option('snapshot') as String?;
    final includeSnapshot = snapshotMode == null &&
        ((ctx.input.option('includeSnapshot') as bool?) ?? false);
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;

    final response = await callExtensionVisible(
      ctx,
      'ext.dusk.type',
      {
        'ref': ref,
        'text': text,
        if (snapshotMode != null)
          'snapshot': snapshotMode
        else
          'includeSnapshot': includeSnapshot.toString(),
        'checkStable': checkStable.toString(),
        'checkReceivesEvents': checkReceivesEvents.toString(),
      },
    );
    reportFrameWarning(ctx, response);
    if (includeSnapshot || wantsJson(ctx)) {
      ctx.output.writeln(jsonEncode(response));
      return 0;
    }

    // `effect.verified` is read back from the live controller, so a formatter
    // or keyboard type that filtered the write shows up here and a bare
    // `✓ Typed into e3` would hide it.
    final effect = response['effect'] as Map<String, dynamic>?;
    _reportNearestTarget(ctx, ref, effect);
    final verified = effect?['verified'] != false;
    if (verified) {
      ctx.output.success('Typed into $ref');
    } else {
      final actual = effect?['value'];
      ctx.output.error(
        actual == null
            ? 'Type not verified: $ref does not hold the text that was typed '
                '("$text")'
            : 'Type not verified: $ref holds "$actual", not the text that was '
                'typed ("$text")',
      );
    }
    final snapshot = response['snapshot'] as String?;
    if (snapshot != null) ctx.output.writeln(snapshot);
    return verified ? 0 : 1;
  }

  /// Names the field that was written when the ref overlapped none, so a
  /// write into a neighbouring field is visible rather than a bare tick.
  void _reportNearestTarget(
    ArtisanContext ctx,
    String ref,
    Map<String, dynamic>? effect,
  ) {
    final target = effect?['target'] as Map<String, dynamic>?;
    if (target?['matchKind'] != 'nearest') return;
    final rect = target!['rect'] as Map<String, dynamic>;
    final label = target['label'] as String?;
    final box = <Object?>[
      rect['x'],
      rect['y'],
      rect['width'],
      rect['height'],
    ].map((v) => _compact(v as num)).toList();
    ctx.output.warning(
      '$ref overlaps no text field; wrote the nearest one'
      '${label == null ? '' : ', "$label",'} at '
      '(${box[0]}, ${box[1]}, ${box[2]}x${box[3]})',
    );
  }

  String _compact(num value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';
}
