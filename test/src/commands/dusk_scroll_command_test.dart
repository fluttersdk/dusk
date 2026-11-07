import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_scroll_command.dart';

/// Stubs [ArtisanContext.callExtension] so tests never hit a real VM Service.
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
  group('DuskScrollCommand', () {
    test('name is dusk:scroll', () {
      expect(DuskScrollCommand().name, equals('dusk:scroll'));
    });

    test('boot is CommandBoot.connected', () {
      expect(DuskScrollCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(DuskScrollCommand().description, isNotEmpty);
    });

    test('handle calls ext.dusk.scroll with ref', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.scroll'));
      expect(ctx.lastParams, containsPair('ref', 'e5'));
    });

    test('handle forwards dy when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'dy': '-300'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('dy', '-300'));
    });

    test('handle forwards dx when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'dx': '100'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('dx', '100'));
    });

    test('handle forwards intoView flag when provided', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'intoView': true}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('intoView', 'true'));
    });

    test('handle returns 1 and prints error when ref is missing', () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: output,
      );

      final code = await DuskScrollCommand().handle(ctx);

      expect(code, equals(1));
      expect(output.content, contains('ref'));
    });

    test('handle returns 0 on success', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5'}),
        output: BufferedOutput(),
      );

      expect(await DuskScrollCommand().handle(ctx), equals(0));
    });

    test('handle passes --direction and --pixels on for the extension to read',
        () async {
      final ctx = _StubContext(
        input:
            MapInput(const {'ref': 'e5', 'direction': 'down', 'pixels': '200'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastMethod, equals('ext.dusk.scroll'));
      expect(ctx.lastParams, containsPair('direction', 'down'));
      expect(ctx.lastParams, containsPair('pixels', '200'));
      expect(ctx.lastParams, isNot(contains('dy')));
    });

    test('handle passes --dy and --dx through untouched', () async {
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'dy': '500', 'dx': '-20'}),
        output: BufferedOutput(),
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('dy', '500'));
      expect(ctx.lastParams, containsPair('dx', '-20'));
      expect(ctx.lastParams, isNot(contains('direction')));
    });

    group('.handle() outcome summary', () {
      test('effect.changed:false says nothing moved and exits 0', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'dy': '300'}),
          output: output,
          response: const {
            'effect': {
              'kind': 'scrollOffset',
              'changed': false,
              'before': 0.0,
              'after': 0.0,
            },
          },
        );

        final code = await DuskScrollCommand().handle(ctx);

        expect(code, equals(0));
        expect(
          output.content,
          contains(
            'Scrolled e5 (nothing moved: not scrollable, or already at the '
            'edge)',
          ),
        );
      });

      test('effect.changed:true keeps the plain summary', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {'ref': 'e5', 'dy': '300'}),
          output: output,
          response: const {
            'effect': {'kind': 'scrollOffset', 'changed': true},
          },
        );

        await DuskScrollCommand().handle(ctx);

        expect(output.content, contains('Scrolled e5'));
        expect(output.content, isNot(contains('nothing moved')));
      });
    });

    test('--snapshot passes the mode through and prints the text after',
        () async {
      final output = BufferedOutput();
      final ctx = _StubContext(
        input: MapInput(const {'ref': 'e5', 'dy': '100', 'snapshot': 'diff'}),
        output: output,
        response: const {
          'scrolled': true,
          'effect': {'kind': 'scrollOffset', 'changed': true},
          'snapshot': '- - text "row 0"\n(1 of 12 lines changed)',
          'snapshotMode': 'diff',
        },
      );

      await DuskScrollCommand().handle(ctx);

      expect(ctx.lastParams, containsPair('snapshot', 'diff'));
      expect(ctx.lastParams!.containsKey('includeSnapshot'), isFalse);
      final String content = output.content;
      expect(content.indexOf('Scrolled e5'), greaterThanOrEqualTo(0));
      expect(
        content.indexOf('Scrolled e5'),
        lessThan(content.indexOf('(1 of 12 lines changed)')),
      );
    });
  });
}
