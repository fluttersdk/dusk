import 'package:magic/magic.dart';

/// Application Service Provider.
///
/// Bind your own services to the IoC container here and perform any bootstrap
/// logic that requires other services to be ready.
class AppServiceProvider extends ServiceProvider {
  AppServiceProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {}
}
