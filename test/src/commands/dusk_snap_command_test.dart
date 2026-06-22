import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_snap_command.dart';

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
  group('DuskSnapCommand', () {
    test('name is dusk:snap', () {
      expect(DuskSnapCommand().name, equals('dusk:snap'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskSnapCommand().boot, equals(CommandBoot.connected));
    });

    test('configure declares --depth option', () {
      final parser = ArgParser();
      DuskSnapCommand().configure(parser);
      expect(parser.options.keys, contains('depth'));
    });

    test('handle calls ext.dusk.snap with no params when --depth omitted',
        () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
        response: const {'snapshot': '- button "Foo" [ref=e1]'},
      );
      final exit = await DuskSnapCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.dusk.snap'));
      // Caller passed nothing; command may add default flags (e.g.
      // includeEnrichers) so we only assert the caller-supplied keys
      // are NOT present.
      expect(ctx.lastParams!.containsKey('depth'), isFalse);
    });

    test('handle forwards --depth to ext.dusk.snap when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'depth': '3'}),
        output: BufferedOutput(),
        response: const {'snapshot': ''},
      );
      await DuskSnapCommand().handle(ctx);
      expect(ctx.lastParams, containsPair('depth', '3'));
    });

    test('handle prints the snapshot string to ctx.output', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {
          'snapshot': '- text "Hello"\n- button "Click" [ref=e1]'
        },
      );
      await DuskSnapCommand().handle(ctx);
      expect(output.content, contains('Hello'));
      expect(output.content, contains('[ref=e1]'));
    });

    test('handle surfaces a renderErrors banner alongside the snapshot',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {
          'snapshot': '- button "Save" [ref=e1]',
          'renderErrors': {
            'count': 2,
            'recent': [
              {
                'type': 'FlutterError',
                'message': 'Incorrect use of ParentDataWidget.',
              },
            ],
            'hint': 'Run dusk:exceptions (CLI) or dusk_exceptions (MCP) for '
                'full messages + stack traces.',
          },
        },
      );
      final exit = await DuskSnapCommand().handle(ctx);
      expect(exit, equals(0));
      // The banner is surfaced (it routes to stderr via ctx.output.error in
      // production; BufferedOutput merges that channel into content for the
      // assertion).
      expect(output.content, contains('2 render error(s) captured'));
      expect(output.content, contains('Incorrect use of ParentDataWidget.'));
      // The snapshot payload is still emitted.
      expect(output.content, contains('[ref=e1]'));
    });

    test('handle falls back to JSON encode when response has no snapshot key',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
        response: const {'note': 'no snapshot key'},
      );
      await DuskSnapCommand().handle(ctx);
      expect(output.content, contains('no snapshot key'));
    });
  });
}
