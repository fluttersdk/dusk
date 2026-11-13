/// CLI-side barrel; intentionally Flutter-free.
///
/// Imported by the consumer's `lib/app/_plugins.g.dart` codegen (which runs
/// under `dart run` on the pure Dart VM, not under `flutter run`). Re-exports
/// the dowel provider class so `dart run dowel list` and
/// `dart run tapir mcp:serve` can wire tapir without dragging the Flutter
/// runtime into the consumer wrapper.
///
/// `dowel`'s `plugins:refresh` generates plugin imports as
/// `<PascalCasePackageName>DowelProvider`, which for this package is
/// [TapirDowelProvider] itself, so no alias is needed.
///
/// Runtime / widget code keeps using `package:tapir/tapir.dart`
/// (the full barrel that re-exports `TapirPlugin` + gesture drivers + adapters +
/// extensions).
library;

export 'src/tapir_dowel_provider.dart' show TapirDowelProvider;
