import 'dart:convert';
import 'dart:developer';

import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/tapir_plugin.dart';
import 'package:tapir/src/extensions/ext_boot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ext.tapir.boot_id', () {
    setUp(() {
      TapirPlugin.aiTestDisableEnvValue = '';
    });

    test('answers the boot id install() minted', () async {
      TapirPlugin.install();

      final ServiceExtensionResponse response = await tapirBootIdHandler(
        'ext.tapir.boot_id',
        const <String, String>{},
      );

      final Map<String, dynamic> payload =
          jsonDecode(response.result!) as Map<String, dynamic>;
      expect(payload['bootId'], TapirPlugin.bootId);
      expect(payload['bootId'], matches(RegExp(r'^[0-9a-z]+-[0-9a-z]+$')));
    });

    test('mintBootId() gives a different id on every boot', () {
      final Set<String> ids = <String>{
        for (int i = 0; i < 50; i++) TapirPlugin.mintBootId(),
      };

      expect(ids, hasLength(50));
    });
  });
}
