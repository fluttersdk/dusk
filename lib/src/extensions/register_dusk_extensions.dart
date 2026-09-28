import 'ext_boot.dart';
import 'ext_checkbox.dart';
import 'ext_close_app.dart';
import 'ext_console.dart';
import 'ext_evaluate.dart';
import 'ext_exceptions.dart';
import 'ext_fill.dart';
import 'ext_find.dart';
import 'ext_focus.dart';
import 'ext_modal_router.dart';
import 'ext_navigation.dart';
import 'ext_observe.dart';
import 'ext_perf.dart';
import 'ext_perf_trace.dart';
import 'ext_pointer.dart';
import 'ext_screenshot.dart';
import 'ext_scroll.dart';
import 'ext_semantics_hold.dart';
import 'ext_snapshot.dart';
import 'ext_text_input.dart';
import 'ext_wait_find.dart';

/// Aggregator. Called once from DuskPlugin.install().
///
/// Each register*Extensions sub-aggregator uses registerExtensionIdempotent
/// so hot-restart safety is built into each registration site (the VM
/// extension table persists across hot-restart; the second registration
/// silently no-ops via the ArgumentError catch).
///
/// Wave 2 additions (alpha-2):
/// - [registerNavigationExtensions] (Step 6): ext.dusk.navigate /
///   navigate_back / get_routes.
/// - [registerEvaluateExtension] (Step 9): ext.dusk.evaluate.
/// - [registerCloseAppExtension] (Step 10): ext.dusk.close_app.
///
/// Wave 3 additions (alpha-2):
/// - [registerFindExtension] (Step 16): ext.dusk.find — Playwright-Locator-
///   style query handle (`q<N>` refs that re-execute the predicates on
///   every action call).
///
/// Steps 7 (press_key) and 8 (select_option) register their handlers INSIDE
/// the pre-existing [registerTextInputExtensions] and
/// [registerScrollExtensions] respectively, so no new aggregator call is
/// needed for them.
///
/// Step 3.4 adds `ext.dusk.wait_for_network_idle` INSIDE
/// [registerWaitFindExtensions]; no new aggregator call needed there either.
///
/// Step 3.5 additions:
/// - [registerConsoleExtensions]: ext.dusk.console — telescope log reader.
/// - [registerExceptionsExtensions]: ext.dusk.exceptions — telescope exception reader.
/// - `ext.dusk.dblclick` is registered INSIDE [registerPointerExtensions].
/// - [registerCheckboxExtensions]: ext.dusk.set_checkbox — checkbox setter.
///
/// Perf trio:
/// - [registerPerfExtensions]: ext.dusk.perf_begin / ext.dusk.perf_end, the
///   measurement session that switches Flutter's profiling flags on (or, in
///   timing mode, touches none), reads the frame, wind and magic counters back
///   through the pointers in `lib/src/utils/perf_readers.dart`, reports ranked
///   insights and restores every flag afterwards; plus ext.dusk.perf_insight,
///   the drill-down into one of those insights.
/// - [registerPerfTraceExtension]: ext.dusk.perf_trace, the closed session's
///   interactions, frames and host rows as Chrome Trace Event JSON.
/// - [registerSemanticsHoldExtension]: ext.dusk.semantics_hold, which releases
///   dusk's semantics handle for one timed window of `dusk:perf_run
///   --semantics-pass` and re-acquires it before perf_end.
///
/// Last, and it has to stay last: [registerBootExtension], ext.dusk.boot_id,
/// the id `DuskPlugin.install()` minted for this boot. `dusk:perf_run` waits
/// for a new one after a hot restart, and reads an answer as every extension
/// above being registered again.
void registerAllDuskExtensions() {
  registerSnapExtension();
  registerPointerExtensions();
  registerTextInputExtensions();
  registerScrollExtensions();
  registerScreenshotExtension();
  registerWaitFindExtensions();
  registerModalRouterExtension();
  registerNavigationExtensions();
  registerEvaluateExtension();
  registerCloseAppExtension();
  registerFindExtension();
  registerConsoleExtensions();
  registerExceptionsExtensions();
  registerCheckboxExtensions();
  registerObserveExtensions();
  registerFocusExtensions();
  // D7: ext.dusk.fill (focus + clear + type + settle + stale-retry).
  // ext.dusk.reset_overlays registers inside registerModalRouterExtension.
  registerFillExtension();
  registerPerfExtensions();
  registerPerfTraceExtension();
  registerSemanticsHoldExtension();
  registerBootExtension();
}
