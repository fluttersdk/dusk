import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluttersdk_dusk/dusk.dart';
import 'package:magic/magic.dart';
import 'config/app.dart';
import 'config/auth.dart';
import 'config/broadcasting.dart';
import 'config/cache.dart';
import 'config/database.dart';
import 'config/logging.dart';
import 'config/network.dart';
import 'config/routing.dart';
import 'config/view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Install DuskPlugin + Wind enricher BEFORE Magic.init so the
  //    enrichers are registered before the widget tree is built.
  if (kDebugMode) {
    DuskPlugin.install();
    WindDuskIntegration.install();
  }

  // 2. Bootstrap Magic framework with full config factories.
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => routingConfig,
      () => viewConfig,
      () => authConfig,
      () => databaseConfig,
      () => networkConfig,
      () => cacheConfig,
      () => loggingConfig,
      () => broadcastingConfig,
    ],
  );

  // 3. Install Magic enricher AFTER Magic.init — some enrichers call
  //    Magic.find<X>() to resolve registered services.
  if (kDebugMode) {
    MagicDuskIntegration.install();
  }

  runApp(const MagicApplication());
}
