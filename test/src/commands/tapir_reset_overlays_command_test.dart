import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_reset_overlays_command.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
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
  group('TapirResetOverlaysCommand', () {
    test('name is tapir:reset_overlays', () {
      expect(TapirResetOverlaysCommand().name, equals('tapir:reset_overlays'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirResetOverlaysCommand().boot, equals(CommandBoot.connected));
    });

    test('handle calls ext.tapir.reset_overlays and returns 0', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'popped': 2},
      );
      final exit = await TapirResetOverlaysCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.reset_overlays'));
    });
  });
}
