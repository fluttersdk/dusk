import 'ext_modal_router.dart';
import 'ext_pointer.dart';
import 'ext_screenshot.dart';
import 'ext_scroll.dart';
import 'ext_snapshot.dart';
import 'ext_text_input.dart';
import 'ext_wait_find.dart';

/// Aggregator. Called once from DuskPlugin.install().
///
/// Each register*Extensions sub-aggregator uses registerExtensionIdempotent
/// so hot-restart safety is built into each registration site (the VM
/// extension table persists across hot-restart; the second registration
/// silently no-ops via the ArgumentError catch).
void registerAllDuskExtensions() {
  registerSnapExtension();
  registerPointerExtensions();
  registerTextInputExtensions();
  registerScrollExtensions();
  registerScreenshotExtension();
  registerWaitFindExtensions();
  registerModalRouterExtension();
}
