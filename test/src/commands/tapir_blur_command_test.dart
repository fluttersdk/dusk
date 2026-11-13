import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_blur_command.dart';

/// Stubs [DowelContext.callExtension] so the test never hits a real VM
/// Service.
class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
    this._response = const {'blurred': true},
  }) : super.bare(input, output);

  final Map<String, dynamic> _response;
  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastMethod = method;
    lastParams = params;
    return _response as T;
  }
}

void main() {
  group('TapirBlurCommand', () {
    test('name is tapir:blur', () {
      expect(TapirBlurCommand().name, equals('tapir:blur'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirBlurCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirBlurCommand().description, isNotEmpty);
    });

    test('handle calls ext.tapir.blur and returns 0', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );

      final code = await TapirBlurCommand().handle(ctx);

      expect(code, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.blur'));
    });

    test(
      'handle prints success line when --includeSnapshot is false',
      () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'includeSnapshot': false}),
          output: output,
        );

        await TapirBlurCommand().handle(ctx);

        expect(output.content, contains('Blurred'));
      },
    );

    test('handle prints JSON payload when --includeSnapshot is true', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'includeSnapshot': true}),
        output: output,
        response: const {'blurred': true, 'snapshot': '- text "foo"'},
      );

      await TapirBlurCommand().handle(ctx);

      expect(output.content, contains('"blurred":true'));
      expect(ctx.lastParams, containsPair('includeSnapshot', 'true'));
    });
  });
}
