import 'package:magic/magic.dart';
import '../app/providers/app_service_provider.dart';
import '../app/providers/route_service_provider.dart';

/// Application Configuration.
Map<String, dynamic> get appConfig => {
  'app': {
    'name': 'Dusk Magic Example',
    'env': 'local',
    'debug': true,
    'key': null,
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => CacheServiceProvider(app),
      (app) => LaunchServiceProvider(app),
      (app) => LocalizationServiceProvider(app),
      (app) => NetworkServiceProvider(app),
      (app) => VaultServiceProvider(app),
      (app) => BroadcastServiceProvider(app),
      (app) => AppServiceProvider(app),
      (app) => AuthServiceProvider(app),
    ],
  },
};
