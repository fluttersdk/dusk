import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_navigate_back_command.dart';

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
  group('DuskNavigateBackCommand', () {
    test('name is dusk:navigate_back', () {
      expect(DuskNavigateBackCommand().name, equals('dusk:navigate_back'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskNavigateBackCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskNavigateBackCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.navigate_back with no params', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await DuskNavigateBackCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.navigate_back'));
      // Command adds includeSnapshot:'false' default; just assert it
      // didn't get any unexpected payload keys.
      expect(
        ctx.lastParams!.keys.where((k) => k != 'includeSnapshot'),
        isEmpty,
      );
    });
  });
}
