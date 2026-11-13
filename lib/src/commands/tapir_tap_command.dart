import 'dart:convert';

import 'package:dowel/dowel.dart';

import 'frame_warning_output.dart';
import 'json_output.dart';
import 'web_visibility.dart';

/// `dowel tapir:tap --ref=<eN>` — synthesize a tap on the element.
class TapirTapCommand extends DowelCommand {
  @override
  String get name => 'tapir:tap';

  @override
  String get description =>
      'Tap a widget by ref token (from prior tapir:snap).';

  @override
  CommandBoot get boot => CommandBoot.connected;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
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
    parser.addOption(
      'snapshot',
      allowed: <String>['full', 'diff', 'none'],
      help:
          'Print the post-tap snapshot after the summary: the whole tree, '
          'only the lines changed since the last snapshot, or nothing. '
          'Overrides --includeSnapshot.',
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
    parser.addFlag(
      'retarget',
      help:
          'Send a tap on a merged boundary to its labelled control. '
          '--no-retarget taps the boundary centre instead.',
      defaultsTo: true,
    );
    parser.addOption(
      'until',
      help:
          'After the tap, poll the live tree for a Text equal to this value '
          'and add an `untilMatched` boolean to the response.',
    );
    parser.addOption(
      'untilTimeoutMs',
      help: 'Timeout in milliseconds for --until polling (default 3000).',
    );
  }

  @override
  Future<int> handle(DowelContext ctx) async {
    final ref = ctx.input.option('ref') as String?;
    if (ref == null || ref.isEmpty) {
      ctx.output.error(
        'Missing --ref=<eN>. Run tapir:snap first to obtain refs.',
      );
      return 1;
    }
    final snapshotMode = ctx.input.option('snapshot') as String?;
    final includeSnapshot =
        snapshotMode == null &&
        ((ctx.input.option('includeSnapshot') as bool?) ?? false);
    final checkStable = (ctx.input.option('checkStable') as bool?) ?? true;
    final checkReceivesEvents =
        (ctx.input.option('checkReceivesEvents') as bool?) ?? true;
    final retarget = (ctx.input.option('retarget') as bool?) ?? true;
    final until = ctx.input.option('until') as String?;
    final untilTimeoutMs = ctx.input.option('untilTimeoutMs') as String?;
    final hasUntil = until != null && until.isNotEmpty;
    final params = <String, String>{
      'ref': ref,
      if (snapshotMode != null)
        'snapshot': snapshotMode
      else
        'includeSnapshot': includeSnapshot.toString(),
      'checkStable': checkStable.toString(),
      'checkReceivesEvents': checkReceivesEvents.toString(),
      if (!retarget) 'retarget': 'false',
      if (hasUntil) 'until': until,
      if (untilTimeoutMs != null && untilTimeoutMs.isNotEmpty)
        'untilTimeoutMs': untilTimeoutMs,
    };
    final response = await callExtensionVisible(ctx, 'ext.tapir.tap', params);
    reportFrameWarning(ctx, response);
    _reportTapOutsideOwner(ctx, response);
    // Print the envelope when the caller asked for it, or when they asked
    // for a field that only lives in it (a snapshot, an `untilMatched`).
    if (wantsJson(ctx) || includeSnapshot || hasUntil) {
      ctx.output.writeln(jsonEncode(response));
      return 0;
    }

    // The summary names the one field worth reading. `effect.changed` is
    // false for a tap the gate accepted that moved nothing, and a bare
    // `✓ Tapped e7` would hide exactly that case.
    final effect = response['effect'] as Map<String, dynamic>?;
    final where = _retargetedNote(response['retargeted']);
    ctx.output.success(
      effect?['changed'] == false
          ? 'Tapped $ref$where (no observable change)'
          : 'Tapped $ref$where',
    );
    final snapshot = response['snapshot'] as String?;
    if (snapshot != null) ctx.output.writeln(snapshot);
    return 0;
  }

  /// The summary suffix for a tap that was sent to the labelled control
  /// instead of the merge boundary's centre (#60); empty for an ordinary tap.
  String _retargetedNote(Object? retargeted) {
    if (retargeted is! Map<String, dynamic>) return '';

    final from = retargeted['from'] as Map<String, dynamic>;
    final to = retargeted['to'] as Map<String, dynamic>;
    final handled = retargeted['centreHandled'] == true
        ? '; the centre has a tap handler of its own, --no-retarget taps that'
        : '';
    return ' on its control at (${to['x']}, ${to['y']}), '
        'not the merged centre (${from['x']}, ${from['y']})$handled';
  }

  /// Prints one stderr line when the tap landed outside the control's own area.
  ///
  /// A merged boundary taps at its own centre, which the gate confirms even
  /// when the real control sits elsewhere (#60). Like the frame banner it goes
  /// to stderr, so the summary on stdout stays what a caller pipes onward.
  void _reportTapOutsideOwner(
    DowelContext ctx,
    Map<String, dynamic>? response,
  ) {
    final outside = response?['tapPointOutsideOwner'] as Map<String, dynamic>?;
    if (outside == null) return;

    final point = outside['point'] as Map<String, dynamic>;
    final owner = outside['ownerRect'] as Map<String, dynamic>;
    ctx.output.error(
      '⚠ The tap landed at (${point['x']}, ${point['y']}), outside the '
      "control's own area (${owner['left']}, ${owner['top']}, "
      '${owner['width']}x${owner['height']}), so it may have hit something '
      'else. Check the result before relying on it.',
    );
  }
}
