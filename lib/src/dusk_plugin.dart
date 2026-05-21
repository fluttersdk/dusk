import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

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
///   `wind_diagnostics_contracts.WindDebugRegistry` instead, read by
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

    // Force Semantics tree on for snapshot extension.
    _semanticsHandle ??= RendererBinding.instance.ensureSemantics();

    // Register all ext.dusk.* extensions.
    registerAllDuskExtensions();

    developer.log(
      '[fluttersdk_dusk] installed (kDebugMode=$kDebugMode, isWeb=$kIsWeb)',
      name: 'dusk',
    );
  }

  static int _installCount = 0;

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
}
