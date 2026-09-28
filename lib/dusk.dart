/// fluttersdk_dusk — E2E driver for Flutter apps (LLM agent + integration test surfaces).
///
/// Public API:
/// - [DuskPlugin]: host-side install entry. Idempotent. Wraps the app's
///   widget root in a RepaintBoundary (no GlobalKey) so the screenshot
///   extension can find it via render-tree walk.
/// - [RefRegistry]: `e<N>` token system for stable element handles across
///   snapshot/action tool calls.
/// - [DuskSnapshotEnricher]: typedef for the snapshot-enricher extension
///   point (Magic ships MagicFormEnricher via this). Wind diagnostics
///   flow through `fluttersdk_wind_diagnostics_contracts.WindDebugRegistry` instead
///   (registered by `Wind.installDebugResolver()`).
/// - [DuskArtisanProvider]: registers 37 dusk:* commands + 36 MCP tool
///   descriptors into artisan.
/// - [buildPerfReport]: the pure builder behind `ext.dusk.perf_end`, callable
///   from a host's conformance test with the same maps the extension reads.
/// - [PerfInteraction] and [activeInteraction]: the interaction a dusk gesture
///   opens inside a perf session, read off the zone as
///   `Zone.current[#fluttersdk_interaction]` or, from frame-zone work, through
///   the active slot.
library;

export 'src/dusk_artisan_provider.dart';
export 'src/dusk_error_capture.dart' show recentCapturedExceptions;
export 'src/dusk_navigate_adapter.dart';
export 'src/dusk_plugin.dart';
export 'src/dusk_snapshot_enricher.dart';
export 'src/extensions/ext_console.dart' show recentLogsReader;
export 'src/extensions/ext_exceptions.dart' show recentExceptionsReader;
export 'src/extensions/ext_wait_find.dart' show pendingHttpCountReader;
export 'src/ref_registry.dart';
export 'src/utils/perf_insights.dart' show PerfMode, buildPerfReport;
export 'src/utils/perf_interaction.dart'
    show PerfInteraction, activeInteraction;
export 'src/utils/perf_readers.dart'
    show
        framePerfReader,
        perfExtrasReader,
        perfInsightContributors,
        perfSessionBeginHook,
        perfSessionEndHook,
        perfTimelineReader;
