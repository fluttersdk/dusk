import 'package:dowel/dowel.dart';

/// Prints the frame-production banner when an extension result carries one.
///
/// Every `ext.tapir.*` success payload gains a `warnings` block while the
/// engine has stopped producing frames (see `lib/src/utils/tapir_response.dart`).
/// Most commands print the raw JSON envelope and the block travels with it,
/// but the ones that summarise (`tapir:snap` prints only the tree, `tapir:tap`
/// prints `✓ Tapped e7`) would drop the single field that explains why the
/// result is not trustworthy.
///
/// Goes to stderr, like the render-error banner, so stdout stays the payload
/// a caller pipes into a tool.
void reportFrameWarning(DowelContext ctx, Map<String, dynamic>? result) {
  final warnings = result?['warnings'] as Map<String, dynamic>?;
  if (warnings == null) return;

  final lifecycle = warnings['lifecycleState'] ?? 'unknown';
  final cause = warnings['platform'] == 'web'
      ? 'A backgrounded browser tab is the usual cause: bring the page to '
            'front and retry.'
      : 'The window is hidden, minimised or occluded, or the display is '
            'asleep: bring the window to front and retry.';
  ctx.output.error(
    '⚠ The app is not producing frames (lifecycle: $lifecycle), so this '
    'result may be stale. $cause',
  );
}
