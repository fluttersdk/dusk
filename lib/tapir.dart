/// tapir: E2E driver for Flutter apps (LLM agent + integration test surfaces).
///
/// Public API:
/// - [TapirPlugin]: host-side install entry. Idempotent.
/// - [RefRegistry]: `e<N>` token system for stable element handles across
///   snapshot/action tool calls, with [RefEntry], [TapirQuery] and
///   [RefBinding].
/// - [TapirSnapshotEnricher]: typedef for the snapshot-enricher extension
///   point (Magic ships MagicFormEnricher via this). Wind diagnostics
///   flow through `wind_kit_diagnostics_contracts.WindDebugRegistry` instead
///   (registered by `Wind.installDebugResolver()`).
/// - [TapirNavigateAdapter]: typedef for the router adapter.
/// - [TapirDowelProvider]: registers the tapir:* commands and the MCP
///   tool descriptors into dowel.
/// - [recentLogsReader], [recentExceptionsReader] (with [ConsoleRequest] and
///   [ExceptionsRequest]), [pendingHttpCountReader] and
///   [recentCapturedExceptions]: the readers a host assigns or reads.
/// - [buildPerfReport]: the pure builder behind `ext.tapir.perf_end`, callable
///   from a host's conformance test with the same maps the extension reads.
/// - [PerfInteraction], [activeInteraction] and [perfInteractionAt]: the
///   interaction a tapir gesture opens inside a perf session, read off the zone
///   as `Zone.current[#tapir_interaction]`, from frame-zone work through
///   the active slot, or from any recorded time through `perfInteractionAt`.
/// - [rendererReader]: the pointer behind the report's `env.renderer`, which a
///   host may reassign.
///
/// Every export names its symbols: what `src/` declares beyond them (the
/// semantics handle, the boot id minting, the ref registry's test helpers)
/// is tapir's own and reachable only through `src/` imports.
library;

export 'src/tapir_dowel_provider.dart' show TapirDowelProvider;
export 'src/tapir_error_capture.dart' show recentCapturedExceptions;
export 'src/tapir_navigate_adapter.dart' show TapirNavigateAdapter;
export 'src/tapir_plugin.dart' show TapirPlugin;
export 'src/tapir_snapshot_enricher.dart' show TapirSnapshotEnricher;
export 'src/extensions/ext_console.dart' show ConsoleRequest, recentLogsReader;
export 'src/extensions/ext_exceptions.dart'
    show ExceptionsRequest, recentExceptionsReader;
export 'src/extensions/ext_wait_find.dart' show pendingHttpCountReader;
export 'src/ref_registry.dart'
    show RefBinding, RefEntry, RefRegistry, TapirQuery;
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
