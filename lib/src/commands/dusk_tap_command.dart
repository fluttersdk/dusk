import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';

import 'frame_warning_output.dart';

/// `artisan dusk:tap --ref=<eN>` — synthesize a tap on the element.
class DuskTapCommand extends ArtisanCommand {
  @override
  String get name => 'dusk:tap';

  @override
  String get description => 'Tap a widget by ref token (from prior dusk:snap).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    parser.addOption(
      'ref',
      help: 'Snapshot ref token (e.g. e1).',
      mandatory: true,
    );
    parser.addFlag(
      'includeSnapshot',
      help: 'Embed the post-tap snapshot YAML in the response.',
      defaultsTo: false,
    );
    parser.addFlag(
      'checkStable',
      help: 'Run the Stable (2-frame rect-unchanged) actionability gate.',
      defaultsTo: true,
    );
    parser.addFlag(
      'checkReceivesEvents',
      help: 'Run the Receives-Events (front-most hit-test) actionability gate.',
      defaultsTo: true,
    );
    parser.addOption(
      'until',
      help: 'After the tap, poll the live tree for a Text equal to this value '
          'and add an `untilMatched` boolean to the response.',
    );
    parser.addOption(
      'untilTimeoutMs',
      help: 'Timeout in milliseconds for --until polling (default 3000).',
    );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error(
        'Missing --ref=<eN>. Run dusk:snap first to obtain refs.',
      );
      return 1;
    }
    final includeSnapshot =
        (ctx.input.option('includeSnapshot') as bool?) ?? false;
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;
    final until = ctx.input.option('until') as String?;
    final untilTimeoutMs = ctx.input.option('untilTimeoutMs') as String?;
    final hasUntil = until != null && until.isNotEmpty;
    final params = <String, String>{
      'ref': ref,
      'includeSnapshot': includeSnapshot.toString(),
      'checkStable': checkStable.toString(),
      'checkReceivesEvents': checkReceivesEvents.toString(),
      if (hasUntil) 'until': until,
      if (untilTimeoutMs != null && untilTimeoutMs.isNotEmpty)
        'untilTimeoutMs': untilTimeoutMs,
    };
    final response = await ctx.callExtension<Map<String, dynamic>>(
      'ext.dusk.tap',
      params,
    );
    reportFrameWarning(ctx, response);
    // The envelope always carries `effect`, and it is the field that says
    // whether the tap did anything, so a bare `✓ Tapped e7` would drop the
    // one thing worth reading. Print the JSON unless the caller has opted
    // out of the extras entirely.
    if (includeSnapshot || hasUntil) {
      ctx.output.writeln(jsonEncode(response));
    } else {
      final effect = response['effect'] as Map<String, dynamic>?;
      final changed = effect?['changed'];
      ctx.output.success(
        changed == false ? 'Tapped $ref (no observable change)' : 'Tapped $ref',
      );
    }
    return 0;
  }
}
