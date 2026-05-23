import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_blur_command.dart';

/// Stubs [ArtisanContext.callExtension] so the test never hits a real VM
/// Service.
class _StubContext extends ArtisanContext {
  _StubContext({
    required ArtisanInput input,
    required ArtisanOutput output,
    Map<String, dynamic> response = const {'blurred': true},
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
  group('DuskBlurCommand', () {
    test('name is dusk:blur', () {
      expect(DuskBlurCommand().name, equals('dusk:blur'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskBlurCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskBlurCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.blur and returns 0', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );

      final code = await DuskBlurCommand().handle(ctx);

      expect(code, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.blur'));
    });

    test('handle prints success line when --includeSnapshot is false',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'includeSnapshot': false}),
        output: output,
      );

      await DuskBlurCommand().handle(ctx);

      expect(output.content, contains('Blurred'));
    });

    test('handle prints JSON payload when --includeSnapshot is true', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'includeSnapshot': true}),
        output: output,
        response: const {'blurred': true, 'snapshot': '- text "foo"'},
      );

      await DuskBlurCommand().handle(ctx);

      expect(output.content, contains('"blurred":true'));
      expect(ctx.lastParams, containsPair('includeSnapshot', 'true'));
    });
  });
}
