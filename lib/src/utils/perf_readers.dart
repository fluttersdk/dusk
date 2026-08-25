/// Four settable cross-package pointers that let dusk read and reset perf
/// state in packages it cannot depend on (frozen contract #10 limits dusk to
/// `fluttersdk_artisan`, `image`, `meta`, `fluttersdk_wind_diagnostics_contracts`;
/// it must not import telescope, wind or magic).
///
/// Each follows `pendingHttpCountReader`'s shape exactly
/// (`ext_wait_find.dart:74`): a settable top-level function defaulting to a
/// no-op, so dusk and the package that assigns it (`magic_devtools`) build
/// independently. `magic_devtools` is the one place dusk, telescope, wind and
/// magic are all visible at once, so it is the only place these can be
/// assigned; dusk only declares and reads them.
library;

/// Reader for the current frame-performance data and liveness signal.
///
/// Defaults to a function returning an empty frame list and a liveness
/// counter of 0, so a host without the perf integration wired gets a
/// structurally-complete empty result rather than a null or a thrown error.
///
/// Hosts that ship `fluttersdk_telescope` wire the real source by writing:
///
/// ```dart
/// framePerfReader = () => {
///   'frames': TelescopeStore.recentFramePerf().map((r) => r.toJson()).toList(),
///   'livenessCounter': FramePerfWatcher.livenessCounter,
/// };
/// ```
///
/// **Contract**: set-once-per-isolate from `MagicPerfIntegration.install()`.
/// Reset to this no-op default by `MagicPerfIntegration.resetForTesting()` so
/// downstream tests asserting the missing-integration default do not see
/// leaked bindings. Returns exactly
/// `{'frames': List<Map<String, Object?>>, 'livenessCounter': int}`; the
/// liveness counter is REQUIRED, not optional, because `ext.dusk.perf_end`'s
/// stalled-engine refusal is computed from it.
Map<String, Object?> Function() framePerfReader = () => <String, Object?>{
      'frames': <Map<String, Object?>>[],
      'livenessCounter': 0,
    };

/// Reader for the magic-side performance extras: controller notify counts
/// keyed by controller runtime type, and route-transition timings.
///
/// Defaults to a function returning empty structures for both keys.
///
/// Hosts wire the real source by writing:
///
/// ```dart
/// perfExtrasReader = () => {
///   'controllerNotifies': MagicPerfIntegration.controllerNotifyCounts,
///   'routeTransitions': MagicPerfIntegration.routeTransitions,
/// };
/// ```
///
/// **Contract**: set-once-per-isolate from `MagicPerfIntegration.install()`.
/// Reset to this no-op default by `MagicPerfIntegration.resetForTesting()`.
/// Returns exactly
/// `{'controllerNotifies': Map<String, int>, 'routeTransitions': List<Map<String, Object?>>}`.
Map<String, Object?> Function() perfExtrasReader = () => <String, Object?>{
      'controllerNotifies': <String, int>{},
      'routeTransitions': <Map<String, Object?>>[],
    };

/// Command that opens a measurement session in the packages dusk cannot
/// import: it zeroes wind's counters and telescope's frame buffer, and turns
/// wind's counting ON.
///
/// The enabling half is not incidental. `WindPerfCounters.enabled` defaults to
/// false and lives in `fluttersdk_wind`, which dusk does not depend on and
/// cannot reach: dusk sees wind only through
/// `fluttersdk_wind_diagnostics_contracts`, and the contract exposes `stats()`
/// and nothing that could flip a flag. So without this hook doing it,
/// `ext.dusk.perf_begin` would produce a report whose wind section reads all
/// zeros while every other section is populated, with no error anywhere to say
/// why. Zeroing without enabling is the same bug wearing a tidier name.
///
/// Defaults to a no-op: a host without the perf integration wired has nothing
/// to open.
///
/// Hosts wire the real thing by writing:
///
/// ```dart
/// perfSessionBeginHook = () {
///   WindPerfCounters.reset();
///   WindPerfCounters.enabled = true;
///   TelescopeStore.clearFramePerf();
/// };
/// ```
///
/// **Contract**: set-once-per-isolate from `MagicPerfIntegration.install()`.
/// Reset to this no-op default by `MagicPerfIntegration.resetForTesting()`.
/// Always paired with [perfSessionEndHook]; see there for why.
void Function() perfSessionBeginHook = () {};

/// Command that closes a measurement session, turning wind's counting back
/// off.
///
/// It exists because [perfSessionBeginHook] turns counting on, and something
/// has to turn it off again. `WindParser.parse` is the hottest path in the
/// framework and runs on every build of every W-widget, so leaving counting
/// enabled after a session would tax every later frame in the app for numbers
/// nobody asked for. It is the same discipline `ext.dusk.perf_end` already
/// applies to the `debugProfile*` flags it restores.
///
/// Counters are deliberately NOT zeroed here: `perf_end` reads them to build
/// its report, and a hook that cleared them would have to run after the read,
/// which is a coupling worth avoiding. The next session's
/// [perfSessionBeginHook] zeroes them instead.
///
/// Defaults to a no-op.
///
/// Hosts wire the real thing by writing:
///
/// ```dart
/// perfSessionEndHook = () {
///   WindPerfCounters.enabled = false;
/// };
/// ```
///
/// **Contract**: set-once-per-isolate from `MagicPerfIntegration.install()`.
/// Reset to this no-op default by `MagicPerfIntegration.resetForTesting()`.
void Function() perfSessionEndHook = () {};
