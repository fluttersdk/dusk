import 'dart:convert';
import 'dart:developer';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/dusk_plugin.dart';
import 'package:fluttersdk_dusk/src/extensions/ext_boot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ext.dusk.boot_id', () {
    setUp(() {
      DuskPlugin.aiTestDisableEnvValue = '';
    });

    test('answers the boot id install() minted', () async {
      DuskPlugin.install();

      final ServiceExtensionResponse response =
          await duskBootIdHandler('ext.dusk.boot_id', const <String, String>{});

      final Map<String, dynamic> payload =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(payload['bootId'], DuskPlugin.bootId);
      expect(payload['bootId'], matches(RegExp(r'^[0-9a-z]+-[0-9a-z]+$')));
    });

    test('mintBootId() gives a different id on every boot', () {
      final Set<String> ids = <String>{
        for (int i = 0; i < 50; i++) DuskPlugin.mintBootId(),
      };

      expect(ids, hasLength(50));
    });
  });
}
