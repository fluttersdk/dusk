import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_close_app_command.dart';

class _StubContext extends DowelContext {
  _StubContext({required DowelInput input, required DowelOutput output})
    : _response = const {},
      super.bare(input, output);

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
  group('TapirCloseAppCommand', () {
    test('name is tapir:close_app', () {
      expect(TapirCloseAppCommand().name, equals('tapir:close_app'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirCloseAppCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirCloseAppCommand().description, isNotEmpty);
    });

    test('handle calls ext.tapir.close_app with no params', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await TapirCloseAppCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.close_app'));
      expect(ctx.lastParams, isEmpty);
    });
  });
}
