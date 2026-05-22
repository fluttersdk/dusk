import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_artisan/artisan.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_right_click_command.dart';

class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
    Map<String, dynamic> response = const {},
  })  : _response = response,
        super.bare(input, output);

  final Map<String, dynamic> _response;
  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(String method,
      [Map<String, dynamic>? params]) async {
    lastMethod = method;
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('DuskRightClickCommand', () {
    test('name is dusk:right_click', () {
      expect(DuskRightClickCommand().name, equals('dusk:right_click'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskRightClickCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --ref + gate + includeSnapshot flags', () {
      final parser = ArgParser();
      DuskRightClickCommand().configure(parser);
      expect(parser.options.keys,
          containsAll(<String>['ref', 'includeSnapshot', 'checkStable', 'checkReceivesEvents']));
    });

    test('handle forwards --ref + flags to ext.dusk.right_click', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7'}),
        output: BufferedOutput(),
      );
      final exit = await DuskRightClickCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.right_click'));
      expect(ctx.lastParams, containsPair('ref', 'e7'));
      expect(ctx.lastParams, containsPair('checkStable', 'true'));
    });

    test('handle returns exit=1 when --ref is missing', () async {
      final ctx = _StubContext(input: MapInput(const {}), output: BufferedOutput());
      final exit = await DuskRightClickCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns exit=1 when --ref is empty', () async {
      final ctx = _StubContext(input: MapInput(const {'ref': ''}), output: BufferedOutput());
      expect(await DuskRightClickCommand().handle(ctx), equals(1));
    });

    test('handle emits JSON envelope when --includeSnapshot=true', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'includeSnapshot': true}),
        output: output,
        response: const {'ref': 'e7', 'snapshot': '- menu'},
      );
      await DuskRightClickCommand().handle(ctx);
      final decoded = jsonDecode(output.content.trim()) as Map<String, dynamic>;
      expect(decoded['snapshot'], equals('- menu'));
    });

    test('handle emits "Right-clicked" success line by default', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(input: MapInput(const {'ref': 'e7'}), output: output);
      await DuskRightClickCommand().handle(ctx);
      expect(output.content, contains('Right-clicked e7'));
    });

    test('handle honours --no-checkReceivesEvents opt-out', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e7', 'checkReceivesEvents': false}),
        output: BufferedOutput(),
      );
      await DuskRightClickCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('checkReceivesEvents', 'false'));
    });
  });
}
