import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_navigate_back_command.dart';

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
  group('TapirNavigateBackCommand', () {
    test('name is tapir:navigate_back', () {
      expect(TapirNavigateBackCommand().name, equals('tapir:navigate_back'));
    });

    test('boot is CommandBoot.connected', () {
      expect(TapirNavigateBackCommand().boot, equals(CommandBoot.connected));
    });

    test('description is non-empty', () {
      expect(TapirNavigateBackCommand().description, isNotEmpty);
    });

    test('handle calls ext.tapir.navigate_back with no params', () async {
      final ctx = _StubContext(
        input: MapInput(const {}),
        output: BufferedOutput(),
      );
      final exit = await TapirNavigateBackCommand().handle(ctx);
      expect(exit, equals(0));
      expect(ctx.lastMethod, equals('ext.tapir.navigate_back'));
      // Command adds includeSnapshot:'false' default; just assert it
      // didn't get any unexpected payload keys.
      expect(
        ctx.lastParams!.keys.where((k) => k != 'includeSnapshot'),
        isEmpty,
      );
    });

    group('.handle() outcome summary', () {
      test('popped:false prints a nothing-to-pop line and exits 0', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: const {'navigatedBack': true, 'popped': false},
        );

        final exit = await TapirNavigateBackCommand().handle(ctx);

        expect(exit, equals(0));
        expect(
          output.content,
          contains('Nothing to pop: already at the root route'),
        );
        expect(output.content, isNot(contains('Popped current route')));
      });

      test('popped:true keeps the plain summary', () async {
        final output = BufferedOutput();
        final ctx = _StubContext(
          input: MapInput(const {}),
          output: output,
          response: const {'navigatedBack': true, 'popped': true},
        );

        await TapirNavigateBackCommand().handle(ctx);

        expect(output.content, contains('Popped current route'));
      });
    });
  });
}
