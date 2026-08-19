import 'package:fluttersdk_artisan/artisan.dart';

/// Prints the frame-production banner when an extension result carries one.
///
/// Every `ext.dusk.*` success payload gains a `warnings` block while the
/// engine has stopped producing frames (see `lib/src/utils/dusk_response.dart`).
/// Most commands print the raw JSON envelope and the block travels with it,
/// but the ones that summarise (`dusk:snap` prints only the tree, `dusk:tap`
/// prints `✓ Tapped e7`) would drop the single field that explains why the
/// result is not trustworthy.
///
/// Goes to stderr, like the render-error banner, so stdout stays the payload
/// a caller pipes into a tool.
void reportFrameWarning(ArtisanContext ctx, Map<String, dynamic>? result) {
  final warnings = result?['warnings'] as Map<String, dynamic>?;
  if (warnings == null) return;

  final lifecycle = warnings['lifecycleState'] ?? 'unknown';
  ctx.output.error(
    '⚠ The app is not producing frames (lifecycle: $lifecycle). The '
    'semantics tree is not being rebuilt and gestures cannot take effect, '
    'so this result may be stale. A backgrounded browser tab is the usual '
    'cause: bring the page to front and retry.',
  );
}
