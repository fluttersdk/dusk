import 'dart:convert';
import 'dart:io';

import 'package:dowel/dowel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/commands/tapir_perf_trace_command.dart';

class _StubContext extends DowelContext {
  _StubContext({
    required DowelInput input,
    required DowelOutput output,
  }) : super.bare(input, output);

  String? lastMethod;
  Map<String, dynamic>? lastParams;

  @override
  Future<T> callExtension<T>(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    lastMethod = method;
    lastParams = params;
    return <String, dynamic>{
      'sessionToken': 'perf-3',
      'traceEvents': <Map<String, dynamic>>[
        <String, dynamic>{'ph': 'X', 'name': 'tap', 'ts': 1, 'dur': 2},
      ],
      'displayTimeUnit': 'ms',
      'otherData': <String, dynamic>{'sessionToken': 'perf-3'},
    } as T;
  }
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tapir_perf_trace_test_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  group('TapirPerfTraceCommand', () {
    test('name is tapir:perf_trace and boot is connected', () {
      expect(TapirPerfTraceCommand().name, 'tapir:perf_trace');
      expect(TapirPerfTraceCommand().boot, CommandBoot.connected);
    });

    test('writes the Chrome Trace JSON and prints only the path', () async {
      final String out = '${temp.path}/traces/run.json';
      final BufferedOutput output = BufferedOutput();
      final _StubContext ctx = _StubContext(
        input: MapInput(<String, dynamic>{'token': 'perf-3', 'out': out}),
        output: output,
      );

      final int code = await TapirPerfTraceCommand().handle(ctx);

      expect(code, 0);
      expect(ctx.lastMethod, 'ext.tapir.perf_trace');
      expect(ctx.lastParams, <String, dynamic>{'token': 'perf-3'});
      expect(output.content.trim(), File(out).absolute.path);
      final Map<String, dynamic> trace =
          jsonDecode(File(out).readAsStringSync()) as Map<String, dynamic>;
      expect(
          trace.keys, <String>['traceEvents', 'displayTimeUnit', 'otherData']);
      expect(trace['traceEvents'], hasLength(1));
    });

    test('omits the token when none is given', () async {
      final _StubContext ctx = _StubContext(
        input: MapInput(<String, dynamic>{'out': '${temp.path}/t.json'}),
        output: BufferedOutput(),
      );

      await TapirPerfTraceCommand().handle(ctx);

      expect(ctx.lastParams, <String, dynamic>{});
    });

    test('a missing --out exits 1 without calling the extension', () async {
      final BufferedOutput output = BufferedOutput();
      final _StubContext ctx = _StubContext(
        input: MapInput(const <String, dynamic>{}),
        output: output,
      );

      expect(await TapirPerfTraceCommand().handle(ctx), 1);
      expect(ctx.lastMethod, isNull);
      expect(output.content, contains('--out'));
    });
  });
}
