import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/dusk_screenshot_command.dart';
import 'commands/dusk_snap_command.dart';
import 'commands/dusk_tap_command.dart';

/// Contributes dusk:* commands to the artisan dispatcher.
///
/// Host integration:
/// ```dart
/// // lib/config/app.dart
/// final appConfig = {
///   'artisan': {
///     'providers': [DuskArtisanProvider.new],
///   },
/// };
/// ```
///
/// V1 ships 3 commands: dusk:snap, dusk:tap, dusk:screenshot. The remaining
/// 10 (type/press_key/hover/drag/scroll/select/wait/navigate/dismiss/routes)
/// follow the same pattern; deferred to V1.x for session-budget reasons.
class DuskArtisanProvider extends ArtisanServiceProvider {
  @override
  String get providerName => 'fluttersdk_dusk';

  @override
  List<ArtisanCommand> commands() => <ArtisanCommand>[
    DuskSnapCommand(),
    DuskTapCommand(),
    DuskScreenshotCommand(),
  ];
}
