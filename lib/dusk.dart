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
/// - [DuskArtisanProvider]: registers 13 dusk:* commands into artisan.
library;

export 'src/dusk_artisan_provider.dart';
export 'src/dusk_navigate_adapter.dart';
export 'src/dusk_plugin.dart';
export 'src/dusk_snapshot_enricher.dart';
export 'src/extensions/ext_console.dart' show recentLogsReader;
export 'src/extensions/ext_exceptions.dart' show recentExceptionsReader;
export 'src/extensions/ext_wait_find.dart' show pendingHttpCountReader;
export 'src/ref_registry.dart';
