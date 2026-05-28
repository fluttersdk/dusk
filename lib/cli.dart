/// CLI-side barrel ; intentionally Flutter-free.
///
/// Imported by the consumer's `lib/app/_plugins.g.dart` codegen (which runs
/// under `dart run` on the pure Dart VM, not under `flutter run`). Re-exports
/// the artisan provider class plus the codegen-convention alias so
/// `dart run artisan list` and `dart run fluttersdk_dusk mcp:serve` can wire
/// dusk without dragging the Flutter runtime into the consumer wrapper.
///
/// Runtime / widget code keeps using `package:fluttersdk_dusk/dusk.dart`
/// (the full barrel that re-exports `DuskPlugin` + gesture drivers + adapters +
/// extensions) and the original [DuskArtisanProvider] symbol.
library;

import 'src/dusk_artisan_provider.dart';

export 'src/dusk_artisan_provider.dart' show DuskArtisanProvider;

/// Codegen-convention alias for [DuskArtisanProvider].
///
/// `fluttersdk_artisan`'s `plugins:refresh` generates plugin imports as
/// `<PascalCasePackageName>ArtisanProvider`; for this package that resolves
/// to `FluttersdkDuskArtisanProvider`. The alias keeps the legacy
/// `DuskArtisanProvider` symbol stable for hand-written callers
/// (magic, uptizm-app) while letting the codegen-generated
/// `_plugins.g.dart` find a class name matching its convention.
typedef FluttersdkDuskArtisanProvider = DuskArtisanProvider;
