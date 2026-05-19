import 'package:magic/magic.dart';

import '../kernel.dart';
import '../../routes/app.dart';

/// Route Service Provider.
///
/// Registers the HTTP kernel and application routes.
class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  void register() {
    registerKernel();
  }

  @override
  Future<void> boot() async {
    registerAppRoutes();
  }
}
