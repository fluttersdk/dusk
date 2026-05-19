import 'package:magic/magic.dart';

import '../resources/views/welcome_view.dart';

/// Application Route Definitions.
///
/// Called by RouteServiceProvider.boot() during the Magic bootstrap lifecycle.
void registerAppRoutes() {
  MagicRoute.page('/', () => const WelcomeView()).title('Welcome');
}
