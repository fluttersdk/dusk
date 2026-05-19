import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_navigate_command.dart';

/// Stubs [ArtisanContext.callExtension] so tests never hit a real VM
/// Service. Mirrors the same shape used across the other dusk:* command
/// tests.
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
  group('DuskNavigateCommand', () {
    test('name is dusk:navigate', () {
      expect(DuskNavigateCommand().name, equals('dusk:navigate'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskNavigateCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskNavigateCommand().description, isNotEmpty);
    });

    test('configure declares --route option', () {
      final parser = ArgParser();
      DuskNavigateCommand().configure(parser);
      expect(parser.options.keys, contains('route'));
    });

    test('handle calls ext.dusk.navigate with the supplied route', () async {
      final ctx = _StubContext(
        input: MapInput(const {'route': '/forms'}),
        output: BufferedOutput(),
      );
      final exit = await DuskNavigateCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.navigate'));
      expect(ctx.lastParams, equals({'route': '/forms'}));
    });

    test('handle returns 1 when --route is missing', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await DuskNavigateCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });

    test('handle returns 1 when --route is empty', () async {
      final ctx = _StubContext(
        input: MapInput(const {'route': ''}),
        output: BufferedOutput(),
      );
      final exit = await DuskNavigateCommand().handle(ctx);
      expect(exit, equals(1));
      expect(ctx.lastMethod, isNull);
    });
  });
}
