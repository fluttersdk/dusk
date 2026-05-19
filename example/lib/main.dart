import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluttersdk_dusk/dusk.dart';

import 'screens/buttons_screen.dart';
import 'screens/drawer_screen.dart';
import 'screens/forms_screen.dart';
import 'screens/home_screen.dart';
import 'screens/inputs_screen.dart';
import 'screens/modals_screen.dart';
import 'screens/scroll_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kDebugMode) {
    DuskPlugin.install();
  }
  runApp(const DuskExampleApp());
}

class DuskExampleApp extends StatelessWidget {
  const DuskExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'fluttersdk_dusk example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/buttons': (_) => const ButtonsScreen(),
        '/inputs': (_) => const InputsScreen(),
        '/scroll': (_) => const ScrollScreen(),
        '/modals': (_) => const ModalsScreen(),
        '/drawer': (_) => const DrawerScreen(),
        '/forms': (_) => const FormsScreen(),
      },
    );
  }
}
