/// What a perf run drives the app through: the driver contract, the
/// environment it was measured on, the exception a run stops with, and the
/// wait for the app's boot id that a restart and a cold start share.
///
/// Here rather than in `dusk_perf_run_command.dart` so the perf library
/// (`perf_actions.dart`, `perf_setup_runner.dart`) depends on no command.
library;

import 'dart:async';

// `hide Error`: the installer's `Error` result would shadow dart:core's.
import 'package:fluttersdk_artisan/artisan.dart' hide Error;

import 'scenario.dart';

/// How often a boot wait asks the app for its boot id.
const Duration kPerfBootPollInterval = Duration(milliseconds: 500);

/// A run that cannot go on, with the sentence to print.
final class PerfRunException implements Exception {
  PerfRunException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Everything `dusk:perf_run` needs from outside the command: the app's
/// `ext.dusk.*` extensions, Chrome's DevTools, the runner's restart and the
/// clock. The production driver talks to artisan; a test drives a fake.
abstract interface class PerfRunDriver {
  /// Calls [method] on the running app. Throws on an extension error.
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, String> params,
  ]);

  /// Sends one DevTools command to the page. Chrome only.
  Future<Map<String, dynamic>> cdp(
    String method, [
    Map<String, dynamic> params,
  ]);

  /// Restarts the app from scratch, a hot restart or a full relaunch as the
  /// build allows, and returns once `ext.dusk.*` answers again.
  Future<void> restart();

  Future<void> pause(Duration duration);

  /// Releases whatever the driver opened.
  Future<void> close();
}

/// What the run was measured on, beyond what the app reports about itself.
final class PerfRunEnvironment {
  const PerfRunEnvironment({
    required this.platform,
    this.device,
    this.emulator = false,
    this.restartMode = 'hot_restart',
    this.host = const <String, Object?>{},
    this.renderer = 'unknown',
  });

  final PerfPlatform platform;

  /// The runner's device id (`chrome`, `emulator-5554`, a simulator UDID).
  final String? device;

  /// An Android emulator or an iOS simulator, whose raster ms are not a
  /// device's.
  final bool emulator;

  /// `hot_restart` on a debug build, `relaunch` on one that cannot.
  final String restartMode;

  /// `uname`, CPU and core count of the machine that ran it.
  final Map<String, Object?> host;

  /// The rendering backend scraped from the run log, or `unknown`.
  final String renderer;
}

/// The boot id the running app's `DuskPlugin.install()` minted, read from
/// `ext.dusk.boot_id` on the main isolate.
///
/// Throws whatever the VM Service throws when the extension does not answer:
/// an RPC error while the app restarts, or on an app built with a dusk older
/// than this one. `dusk:perf_campaign` polls it after each cold start.
Future<String> readDuskBootId(VmServiceClient client) async {
  final String isolateId = await client.getMainIsolateId();
  final Map<String, dynamic> result =
      await client.callServiceExtension<Map<String, dynamic>>(
    'ext.dusk.boot_id',
    isolateId: isolateId,
  );
  return result['bootId'] as String;
}

/// Polls until `ext.dusk.boot_id` answers with an id other than [replacing]
/// (any id when [replacing] is null, after a relaunch), which is when
/// `main()` has run `DuskPlugin.install()` again. The boot id registers last,
/// so every other `ext.dusk.*` answers by then.
///
/// The isolate id proves nothing: DWDS keeps `"1"` across a web hot restart.
/// While the app restarts the extension answers with errors (DWDS -32603 for
/// one not registered yet, no isolate, an isolate going away); those are the
/// state being waited out, retried every [pollInterval] until [timeout], and
/// the last one is named when it runs out. A read that hangs is cut at the
/// time left, so [timeout] holds.
Future<void> awaitDuskBoot(
  VmServiceClient client, {
  required String? replacing,
  required Duration timeout,
  Duration pollInterval = kPerfBootPollInterval,
}) =>
    pollDuskBoot(
      () => readDuskBootId(client),
      replacing: replacing,
      timeout: timeout,
      pollInterval: pollInterval,
      failure: 'the app did not come back within ${timeout.inSeconds} s of '
          'the restart',
    );

/// The loop behind [awaitDuskBoot], over any boot id reader: [read] is asked
/// every [pollInterval], waited out through [pause], until it answers an id
/// other than [replacing] or [timeout] runs out. The poll count is capped
/// too, so the budget holds on a [pause] that returns at once.
///
/// Throws [PerfRunException] with [failure], then the last error when there
/// was one, once the budget is spent. No read starts once it is: the last
/// answer named is the app's.
Future<void> pollDuskBoot(
  Future<String> Function() read, {
  required String? replacing,
  required Duration timeout,
  required String failure,
  Duration pollInterval = kPerfBootPollInterval,
  Future<void> Function(Duration duration) pause = _delay,
}) async {
  final Stopwatch clock = Stopwatch()..start();
  final int maxPolls = pollInterval.inMicroseconds <= 0
      ? 1
      : timeout.inMicroseconds ~/ pollInterval.inMicroseconds + 1;
  Object? last;
  for (int poll = 1;; poll++) {
    try {
      final String id = await read().timeout(timeout - clock.elapsed);
      if (id != replacing) return;
      last = null;
    } on Exception catch (e) {
      last = e;
    } on StateError catch (e) {
      last = e;
    }
    if (poll >= maxPolls || clock.elapsed >= timeout) break;
    await pause(pollInterval);
    // A read with no time left would be cut before any reply, and its
    // TimeoutException would stand in for the app's own last answer.
    if (clock.elapsed >= timeout) break;
  }
  throw PerfRunException(
    '$failure${last == null ? '' : ' (last answer: $last)'}.',
  );
}

Future<void> _delay(Duration duration) => Future<void>.delayed(duration);
