/// Three settable cross-package pointers that let dusk read and reset perf
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

/// Command that clears wind's perf counters and telescope's frame buffer at
/// the start of a new measurement session.
///
/// Defaults to a no-op: a host without the perf integration wired has
/// nothing to reset. Without this hook `ext.dusk.perf_begin` would have no
/// way to zero anything and every session would report the sum of all
/// previous ones.
///
/// Hosts wire the real reset by writing:
///
/// ```dart
/// perfSessionResetHook = () {
///   WindPerfCounters.reset();
///   TelescopeStore.clearFramePerf();
/// };
/// ```
///
/// **Contract**: set-once-per-isolate from `MagicPerfIntegration.install()`.
/// Reset to this no-op default by `MagicPerfIntegration.resetForTesting()`.
void Function() perfSessionResetHook = () {};
