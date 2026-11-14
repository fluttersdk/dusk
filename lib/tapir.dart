/// tapir: E2E driver for Flutter apps (LLM agent + integration test surfaces).
///
/// Public API:
/// - [TapirPlugin]: host-side install entry. Idempotent.
/// - [RefRegistry]: `e<N>` token system for stable element handles across
///   snapshot/action tool calls.
/// - [TapirSnapshotEnricher]: typedef for the snapshot-enricher extension
///   point (Magic ships MagicFormEnricher via this). Wind diagnostics
///   flow through `wind_kit_diagnostics_contracts.WindDebugRegistry` instead
///   (registered by `Wind.installDebugResolver()`).
/// - [TapirDowelProvider]: registers the tapir:* commands and the MCP
///   tool descriptors into dowel.
/// - [buildPerfReport]: the pure builder behind `ext.tapir.perf_end`, callable
///   from a host's conformance test with the same maps the extension reads.
/// - [PerfInteraction], [activeInteraction] and [perfInteractionAt]: the
///   interaction a tapir gesture opens inside a perf session, read off the zone
///   as `Zone.current[#tapir_interaction]`, from frame-zone work through
///   the active slot, or from any recorded time through `perfInteractionAt`.
/// - [rendererReader]: the pointer behind the report's `env.renderer`, which a
///   host may reassign.
library;

export 'src/tapir_dowel_provider.dart';
export 'src/tapir_error_capture.dart' show recentCapturedExceptions;
export 'src/tapir_navigate_adapter.dart';
export 'src/tapir_plugin.dart';
export 'src/tapir_snapshot_enricher.dart';
export 'src/extensions/ext_console.dart' show recentLogsReader;
export 'src/extensions/ext_exceptions.dart' show recentExceptionsReader;
export 'src/extensions/ext_wait_find.dart' show pendingHttpCountReader;
export 'src/ref_registry.dart';
export 'src/utils/perf_insights.dart' show PerfMode, buildPerfReport;
export 'src/utils/perf_interaction.dart'
    show PerfInteraction, activeInteraction, perfInteractionAt;
export 'src/utils/perf_readers.dart'
    show
        framePerfReader,
        perfExtrasReader,
        perfInsightContributors,
        perfSessionBeginHook,
        perfSessionEndHook,
        perfTimelineReader,
        rendererReader;
