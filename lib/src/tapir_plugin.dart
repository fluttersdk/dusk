import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'tapir_error_capture.dart';
import 'tapir_log_capture.dart';
import 'tapir_navigate_adapter.dart';
import 'tapir_snapshot_enricher.dart';
import 'extensions/register_tapir_extensions.dart';

/// tapir plugin install entry. Idempotent.
///
/// Host integration:
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   if (!kReleaseMode) {
///     TapirPlugin.install();
///   }
///   runApp(!kReleaseMode ? RepaintBoundary(child: app) : app);
/// }
/// ```
///
/// The consumer gates with `!kReleaseMode`, so a debug AND a profile build
/// both carry TapirPlugin (a profile build is what a real perf session runs
/// against); release builds tree-shake the entire branch on every platform
/// (web dart2js, desktop + mobile dart2native AOT).
///
/// Extension points:
/// - [enrichers]: live-read list of snapshot enrichers. Magic registers
///   MagicFormEnricher + MagicNavigationEnricher via this. Wind no longer
///   uses this list as of wind alpha-10; wind diagnostics flow through
///   `wind_kit_diagnostics_contracts.WindDebugRegistry` instead, read by
///   `ext_snapshot.dart` / `ext_observe.dart` directly.
class TapirPlugin {
  TapirPlugin._();

  /// Active enricher chain. The snapshot extension iterates this list in
  /// insertion order on every snapshot call (live read; mid-session adds
  /// are picked up immediately).
  static final List<TapirSnapshotEnricher> enrichers =
      <TapirSnapshotEnricher>[];

  /// Consumer-registered router adapter consulted by `ext.tapir.navigate`
  /// before falling back to [SystemNavigator.routeInformationUpdated].
  /// Null when no adapter is wired — tapir stays framework-agnostic.
  ///
  /// See [TapirNavigateAdapter] for the contract.
  static TapirNavigateAdapter? get navigateAdapter => _navigateAdapter;
  static TapirNavigateAdapter? _navigateAdapter;

  /// Wires a router adapter. Subsequent calls overwrite the previous
  /// adapter so hot-reload tests can rebind cleanly. Passing `null`
  /// clears the adapter (back to framework-agnostic broadcast).
  static void registerNavigateAdapter(TapirNavigateAdapter? adapter) {
    _navigateAdapter = adapter;
  }

  /// Idempotent install. Safe to call multiple times within the same
  /// isolate lifetime. Hot-restart resets the counter naturally (statics
  /// re-run their initializers); the second real install completes fresh.
  static void install() {
    final disable = aiTestDisableEnvValue.toLowerCase().trim();
    if (disable == '1' || disable == 'true' || disable == 'yes') {
      developer.log(
        '[tapir] install() skipped — TAPIR_DISABLE=$aiTestDisableEnvValue set.',
        name: 'tapir',
      );
      return;
    }
    if (_installCount > 0) {
      developer.log(
        '[tapir] install() called ${_installCount + 1} times — '
        'skipping duplicate.',
        name: 'tapir',
      );
      _installCount++;
      return;
    }
    _installCount++;

    // A fresh id for this run of main(), minted before the extension that
    // reports it registers: tapir:perf_run tells a restarted app by it.
    _bootId = mintBootId();

    // Force Semantics tree on for snapshot extension.
    _semanticsHandle ??= RendererBinding.instance.ensureSemantics();

    // Register all ext.tapir.* extensions.
    registerAllTapirExtensions();

    // Capture non-fatal FlutterErrors (incl. overflow) so ext.tapir.exceptions
    // surfaces them without crumbs. Chains the prior handler.
    installErrorCapture();

    // Capture debugPrint output so ext.tapir.console surfaces logs even when
    // crumbs is absent. Chains the prior debugPrint callback.
    installLogCapture();

    developer.log(
      '[tapir] installed (kDebugMode=$kDebugMode, isWeb=$kIsWeb)',
      name: 'tapir',
    );
  }

  static int _installCount = 0;

  /// The id [install] minted for this run of `main()`, answered by
  /// `ext.tapir.boot_id`; null before [install].
  ///
  /// A hot restart re-runs `main()` and so mints a new one, on the web too,
  /// where the isolate id does not change.
  static String? get bootId => _bootId;
  static String? _bootId;

  /// A boot id: the wall clock in microseconds and a random suffix, base 36,
  /// so two boots in the same microsecond still differ.
  @visibleForTesting
  static String mintBootId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_random.nextInt(1 << 30).toRadixString(36)}';

  static final Random _random = Random();

  /// Exposes [_installCount] for tests.
  @visibleForTesting
  static int get installCount => _installCount;

  /// Env-var kill switch (build-time via `--dart-define=TAPIR_DISABLE=1`).
  @visibleForTesting
  static String aiTestDisableEnvValue = const String.fromEnvironment(
    'TAPIR_DISABLE',
    defaultValue: '',
  );

  static SemanticsHandle? _semanticsHandle;
  static bool _semanticsReleased = false;

  /// Whether [releaseSemantics] dropped tapir's semantics handle and
  /// [acquireSemantics] has not restored it yet.
  ///
  /// While true the semantics tree is gone unless something else holds a
  /// handle, so nothing may resolve a target through it: `ext.tapir.tap` and
  /// `ext.tapir.drag` dispatch by coordinates and report the gate's checks as
  /// skipped.
  static bool get semanticsReleased => _semanticsReleased;

  /// Drops the handle [install] took, so the framework stops building the
  /// semantics tree every frame. Returns whether one was held.
  ///
  /// Only `ext.tapir.semantics_hold` calls this, and only inside an open perf
  /// session: tapir_perf_run's semantics pass measures what the app costs
  /// without the tree, and a handle left released outside that window would
  /// break every snapshot and ref-based action that follows.
  static bool releaseSemantics() {
    final SemanticsHandle? handle = _semanticsHandle;
    if (handle == null) return false;
    handle.dispose();
    _semanticsHandle = null;
    _semanticsReleased = true;
    return true;
  }

  /// Takes tapir's semantics handle again. Returns whether it had to.
  ///
  /// The tree does not exist the moment this returns: the framework schedules
  /// the initial semantics build for the next frame, so a caller that needs
  /// the root node awaits one.
  static bool acquireSemantics() {
    _semanticsReleased = false;
    if (_semanticsHandle != null) return false;
    _semanticsHandle = RendererBinding.instance.ensureSemantics();
    return true;
  }

  /// Disposes whatever handle this class holds and clears the released flag,
  /// so a test leaves neither a live handle (the harness asserts every one is
  /// disposed) nor a released state for the next test to read.
  @visibleForTesting
  static void resetSemanticsForTesting() {
    _semanticsHandle?.dispose();
    _semanticsHandle = null;
    _semanticsReleased = false;
  }
}
