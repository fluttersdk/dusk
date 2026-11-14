import 'dart:convert';
import 'dart:developer';

import 'package:flutter/semantics.dart' show SemanticsBinding;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/extensions/ext_boot.dart';
import 'package:tapir/src/ref_registry.dart';
import 'package:tapir/src/tapir_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ext.tapir.boot_id', () {
    Future<Map<String, dynamic>> bootPayload() async {
      final ServiceExtensionResponse response = await tapirBootIdHandler(
        'ext.tapir.boot_id',
        const <String, String>{},
      );
      return jsonDecode(response.result!) as Map<String, dynamic>;
    }

    test('answers the boot id install() minted', () async {
      TapirPlugin.install();

      final Map<String, dynamic> payload = await bootPayload();

      expect(payload['bootId'], TapirPlugin.bootId);
      expect(payload['bootId'], matches(RegExp(r'^[0-9a-z]+-[0-9a-z]+$')));
    });

    test('reports the semantics state and the enricher count, which '
        'tapir:doctor reads from the running app', () async {
      TapirPlugin.install();
      String? noop(Element element, RefRegistry refs) => null;
      TapirPlugin.enrichers.add(noop);
      addTearDown(() => TapirPlugin.enrichers.remove(noop));

      final Map<String, dynamic> payload = await bootPayload();

      expect(
        payload['semanticsEnabled'],
        SemanticsBinding.instance.semanticsEnabled,
      );
      expect(payload['enrichers'], TapirPlugin.enrichers.length);
      expect(payload['enrichers'], greaterThan(0));
    });

    test('mintTapirBootId() gives a different id on every boot', () {
      final Set<String> ids = <String>{
        for (int i = 0; i < 50; i++) mintTapirBootId(),
      };

      expect(ids, hasLength(50));
    });
  });
}
