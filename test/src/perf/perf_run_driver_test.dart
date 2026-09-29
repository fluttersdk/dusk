import 'dart:async';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/perf/perf_run_driver.dart';

void main() {
  // -------------------------------------------------------------------------
  // The restart wait
  // -------------------------------------------------------------------------

  group('awaitDuskBoot()', () {
    const Duration tick = Duration(milliseconds: 1);

    test(
        'returns once the boot id changes, though the isolate id stays "1" '
        'as it does under DWDS', () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>[
        'boot-a',
        Exception('RPCError -32603: ext.dusk.boot_id is not registered'),
        StateError('VM Service reported no isolates'),
        'boot-b',
      ]);

      await awaitDuskBoot(
        vm,
        replacing: 'boot-a',
        timeout: const Duration(seconds: 5),
        pollInterval: tick,
      );

      expect(vm.isolateIds.toSet(), <String>{'1'});
      expect(vm.answered, 4);
    });

    test('times out with the restart message while the boot id never changes',
        () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>['boot-a']);

      await expectLater(
        awaitDuskBoot(
          vm,
          replacing: 'boot-a',
          timeout: const Duration(milliseconds: 50),
          pollInterval: tick,
        ),
        throwsA(
          isA<PerfRunException>().having(
            (PerfRunException e) => e.message,
            'message',
            contains('the app did not come back within 0 s of the restart'),
          ),
        ),
      );
    });

    test('names the last error when the app never answers', () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>[
        Exception('RPCError -32601: method not found'),
      ]);

      await expectLater(
        awaitDuskBoot(
          vm,
          replacing: 'boot-a',
          timeout: const Duration(milliseconds: 50),
          pollInterval: tick,
        ),
        throwsA(
          isA<PerfRunException>().having(
            (PerfRunException e) => e.message,
            'message',
            contains('-32601'),
          ),
        ),
      );
    });

    test('after a relaunch the first boot id that answers is enough', () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>[
        StateError('VM Service reported no isolates'),
        'boot-z',
      ]);

      await awaitDuskBoot(
        vm,
        replacing: null,
        timeout: const Duration(seconds: 5),
        pollInterval: tick,
      );

      expect(vm.answered, 2);
    });
  });

  group('readDuskBootId()', () {
    test('asks the main isolate for ext.dusk.boot_id', () async {
      final _FakeVmClient vm = _FakeVmClient(<Object>['boot-a']);

      expect(await readDuskBootId(vm), 'boot-a');
      expect(vm.methods.single, 'ext.dusk.boot_id');
    });
  });

  group('pollDuskBoot()', () {
    test(
        'never reads once the budget is spent, so the last answer is the '
        'app\'s, not a zero timeout', () async {
      int reads = 0;

      await expectLater(
        pollDuskBoot(
          () {
            reads++;
            if (reads == 1) {
              return Future<String>.error(Exception('RPCError -32603'));
            }
            return Completer<String>().future;
          },
          replacing: null,
          timeout: const Duration(milliseconds: 50),
          pollInterval: const Duration(milliseconds: 10),
          pause: (Duration _) =>
              Future<void>.delayed(const Duration(milliseconds: 80)),
          failure: 'the app did not come back',
        ),
        throwsA(
          isA<PerfRunException>().having(
            (PerfRunException e) => e.message,
            'message',
            'the app did not come back (last answer: Exception: RPCError '
                '-32603).',
          ),
        ),
      );
      expect(reads, 1);
    });

    test(
        'stops at its poll cap on a pause that returns at once, naming the '
        'failure and the last answer', () async {
      int reads = 0;
      int pauses = 0;

      await expectLater(
        pollDuskBoot(
          () async {
            reads++;
            throw StateError('no isolate yet');
          },
          replacing: null,
          timeout: const Duration(seconds: 2),
          pollInterval: const Duration(milliseconds: 500),
          pause: (Duration _) async => pauses++,
          failure: 'the app did not answer ext.dusk.boot_id within 2 s of '
              'the start',
        ),
        throwsA(
          isA<PerfRunException>().having(
            (PerfRunException e) => e.message,
            'message',
            'the app did not answer ext.dusk.boot_id within 2 s of the start '
                '(last answer: Bad state: no isolate yet).',
          ),
        ),
      );
      expect(reads, 5);
      expect(pauses, 4);
    });
  });
}

/// A VM Service client whose main isolate is always `"1"`, as DWDS reports
/// it across a hot restart, and whose `ext.dusk.boot_id` answers come from
/// a script: a String is a boot id, anything else is thrown. The last entry
/// repeats.
final class _FakeVmClient implements VmServiceClient {
  _FakeVmClient(this.script);

  final List<Object> script;
  final List<String> isolateIds = <String>[];
  final List<String> methods = <String>[];
  int answered = 0;

  @override
  Future<String> getMainIsolateId() async => '1';

  @override
  Future<List<String>> getExtensionRPCs(String isolateId) async =>
      const <String>['ext.dusk.perf_begin', 'ext.dusk.boot_id'];

  @override
  Future<T> callServiceExtension<T>(
    String method, {
    required String isolateId,
    Map<String, dynamic>? params,
  }) async {
    methods.add(method);
    isolateIds.add(isolateId);
    final Object next =
        script[answered < script.length ? answered : script.length - 1];
    answered++;
    if (next is String) return <String, dynamic>{'bootId': next} as T;
    throw next;
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
