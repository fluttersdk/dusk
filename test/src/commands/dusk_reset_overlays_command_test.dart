import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_reset_overlays_command.dart';

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
  group('DuskResetOverlaysCommand', () {
    test('name is dusk:reset_overlays', () {
      expect(DuskResetOverlaysCommand().name, equals('dusk:reset_overlays'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskResetOverlaysCommand().boot, equals(CommandBoot.connected));
    });

    test('handle calls ext.dusk.reset_overlays and returns 0', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'popped': 2},
      );
      final exit = await DuskResetOverlaysCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.reset_overlays'));
    });
  });
}
