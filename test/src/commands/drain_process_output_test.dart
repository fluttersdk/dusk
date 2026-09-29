import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/commands/dusk_perf_campaign_command.dart';

void main() {
  group('drainProcessOutput()', () {
    test(
        'streams that closed before the exit are read whole, at once, '
        'with no note', () async {
      // The order a short-lived process produces: output, then the pipes
      // close, and only then does the exit code arrive.
      final StreamController<List<int>> out = StreamController<List<int>>();
      final StreamController<List<int>> err = StreamController<List<int>>();
      final Completer<int> exit = Completer<int>();
      final Stopwatch clock = Stopwatch()..start();

      final Future<({int exitCode, String stdout, String stderr})> drained =
          drainProcessOutput(
        stdout: out.stream,
        stderr: err.stream,
        exitCode: exit.future,
        grace: const Duration(seconds: 2),
      );
      out.add(utf8.encode('started\n'));
      await out.close();
      await err.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      exit.complete(3);
      final ({int exitCode, String stdout, String stderr}) result =
          await drained;

      expect(result.exitCode, 3);
      expect(result.stdout, 'started\n');
      expect(result.stderr, isEmpty);
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('a pipe still open after the exit is cut at the grace, with a note',
        () async {
      final StreamController<List<int>> out = StreamController<List<int>>();
      final StreamController<List<int>> err = StreamController<List<int>>();

      final Future<({int exitCode, String stdout, String stderr})> drained =
          drainProcessOutput(
        stdout: out.stream,
        stderr: err.stream,
        exitCode: Future<int>.value(0),
        grace: const Duration(milliseconds: 50),
      );
      out.add(utf8.encode('up\n'));
      final ({int exitCode, String stdout, String stderr}) result =
          await drained;

      expect(result.stdout, 'up\n');
      expect(result.stderr, contains('still holds its stdout or stderr'));
      expect(out.hasListener, isFalse);
      await err.close();
    });

    test(
        'a pipe error before the exit is reported, not thrown, and the other '
        'pipe is released', () async {
      final StreamController<List<int>> out = StreamController<List<int>>();
      final StreamController<List<int>> err = StreamController<List<int>>();
      final Completer<int> exit = Completer<int>();

      final Future<({int exitCode, String stdout, String stderr})> drained =
          drainProcessOutput(
        stdout: out.stream,
        stderr: err.stream,
        exitCode: exit.future,
        grace: const Duration(seconds: 2),
      );
      out.addError(const SocketException('pipe broken'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      exit.complete(1);
      final ({int exitCode, String stdout, String stderr}) result =
          await drained;

      expect(result.exitCode, 1);
      expect(result.stderr, contains('pipe broken'));
      expect(err.hasListener, isFalse);
      await out.close();
      await err.close();
    });

    test('a malformed byte decodes to U+FFFD instead of throwing', () async {
      final ({int exitCode, String stdout, String stderr}) result =
          await drainProcessOutput(
        stdout: Stream<List<int>>.fromIterable(<List<int>>[
          <int>[0x6f, 0x6b, 0xff],
        ]),
        stderr: const Stream<List<int>>.empty(),
        exitCode: Future<int>.value(0),
        grace: const Duration(seconds: 1),
      );

      expect(result.stdout, 'ok\u{FFFD}');
    });
  });
}
