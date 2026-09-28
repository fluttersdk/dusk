import 'dart:developer' as developer;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'dusk_error_capture.dart';
import 'dusk_log_capture.dart';
import 'dusk_navigate_adapter.dart';
import 'dusk_snapshot_enricher.dart';
import 'extensions/register_dusk_extensions.dart';

/// fluttersdk_dusk plugin install entry. Idempotent.
///
/// Host integration:
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   if (kDebugMode) {
///     DuskPlugin.install();
///   }
///   runApp(kDebugMode ? RepaintBoundary(child: app) : app);
/// }
/// ```
///
/// V1 compile-time gate is just `kDebugMode` — release builds tree-shake
/// the entire DuskPlugin branch on every platform (web dart2js, desktop +
/// mobile dart2native AOT).
///
/// Extension points:
/// - [enrichers]: live-read list of snapshot enrichers. Magic registers
///   MagicFormEnricher + MagicNavigationEnricher via this. Wind no longer
///   uses this list as of wind alpha-10; wind diagnostics flow through
///   `fluttersdk_wind_diagnostics_contracts.WindDebugRegistry` instead, read by
///   `ext_snapshot.dart` / `ext_observe.dart` directly.
class DuskPlugin {
  DuskPlugin._();

  /// Active enricher chain. The snapshot extension iterates this list in
  /// insertion order on every snapshot call (live read; mid-session adds
  /// are picked up immediately).
  static final List<DuskSnapshotEnricher> enrichers = <DuskSnapshotEnricher>[];

  /// Consumer-registered router adapter consulted by `ext.dusk.navigate`
  /// before falling back to [SystemNavigator.routeInformationUpdated].
  /// Null when no adapter is wired — dusk stays framework-agnostic.
  ///
  /// See [DuskNavigateAdapter] for the contract.
  static DuskNavigateAdapter? get navigateAdapter => _navigateAdapter;
  static DuskNavigateAdapter? _navigateAdapter;

  /// Wires a router adapter. Subsequent calls overwrite the previous
  /// adapter so hot-reload tests can rebind cleanly. Passing `null`
  /// clears the adapter (back to framework-agnostic broadcast).
  static void registerNavigateAdapter(DuskNavigateAdapter? adapter) {
    _navigateAdapter = adapter;
  }

  /// Idempotent install. Safe to call multiple times within the same
  /// isolate lifetime. Hot-restart resets the counter naturally (statics
  /// re-run their initializers); the second real install completes fresh.
  static void install() {
    final disable = aiTestDisableEnvValue.toLowerCase().trim();
    if (disable == '1' || disable == 'true' || disable == 'yes') {
      developer.log(
        '[fluttersdk_dusk] install() skipped — DUSK_DISABLE=$aiTestDisableEnvValue set.',
        name: 'dusk',
      );
      return;
    }
    if (_installCount > 0) {
      developer.log(
        '[fluttersdk_dusk] install() called ${_installCount + 1} times — '
        'skipping duplicate.',
        name: 'dusk',
      );
      _installCount++;
      return;
    }
    _installCount++;

    // A fresh id for this run of main(), minted before the extension that
    // reports it registers: dusk:perf_run tells a restarted app by it.
    _bootId = mintBootId();

    // Force Semantics tree on for snapshot extension.
    _semanticsHandle ??= RendererBinding.instance.ensureSemantics();

    // Register all ext.dusk.* extensions.
    registerAllDuskExtensions();

    // Capture non-fatal FlutterErrors (incl. overflow) so ext.dusk.exceptions
    // surfaces them without telescope. Chains the prior handler.
    installErrorCapture();

    // Capture debugPrint output so ext.dusk.console surfaces logs even when
    // telescope is absent. Chains the prior debugPrint callback.
    installLogCapture();

    developer.log(
      '[fluttersdk_dusk] installed (kDebugMode=$kDebugMode, isWeb=$kIsWeb)',
      name: 'dusk',
    );
  }

  static int _installCount = 0;

  /// The id [install] minted for this run of `main()`, answered by
  /// `ext.dusk.boot_id`; null before [install].
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

  /// Env-var kill switch (build-time via `--dart-define=DUSK_DISABLE=1`).
  @visibleForTesting
  static String aiTestDisableEnvValue = const String.fromEnvironment(
    'DUSK_DISABLE',
    defaultValue: '',
  );

  static SemanticsHandle? _semanticsHandle;
  static bool _semanticsReleased = false;

  /// Whether [releaseSemantics] dropped dusk's semantics handle and
  /// [acquireSemantics] has not restored it yet.
  ///
  /// While true the semantics tree is gone unless something else holds a
  /// handle, so nothing may resolve a target through it: `ext.dusk.tap` and
  /// `ext.dusk.drag` dispatch by coordinates and report the gate's checks as
  /// skipped.
  static bool get semanticsReleased => _semanticsReleased;

  /// Drops the handle [install] took, so the framework stops building the
  /// semantics tree every frame. Returns whether one was held.
  ///
  /// Only `ext.dusk.semantics_hold` calls this, and only inside an open perf
  /// session: dusk_perf_run's semantics pass measures what the app costs
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

  /// Takes dusk's semantics handle again. Returns whether it had to.
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
