import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluttersdk_dusk/dusk.dart';
import 'package:magic/dusk_integration.dart';
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

  // 1. Install DuskPlugin + Wind diagnostics resolver BEFORE Magic.init so
  //    the wiring is in place before the widget tree is built.
  if (kDebugMode) {
    DuskPlugin.install();
    Wind.installDebugResolver();
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
