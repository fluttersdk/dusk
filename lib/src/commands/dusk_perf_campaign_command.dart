import 'dart:async';
import 'dart:convert';
import 'dart:io';

// `hide Error`: the installer's `Error` result would shadow dart:core's.
import 'package:fluttersdk_artisan/artisan.dart' hide Error;

import '../perf/campaign.dart';
import '../perf/perf_actions.dart';
import '../perf/perf_redaction.dart';
import '../perf/perf_run_driver.dart';
import '../perf/perf_setup_runner.dart';
import '../perf/perf_support.dart';
import '../perf/scenario.dart';
import 'dusk_perf_run_command.dart';
import 'json_output.dart';

/// How long a stopped app may keep its pid and its ports. artisan's stop
/// sends SIGTERM and returns, and its start fails at once on a held port.
const Duration _kStopBudget = Duration(seconds: 30);
const Duration _kStopPollInterval = Duration(milliseconds: 250);

/// How long a cold start may take before `ext.dusk.boot_id` answers: the
/// VM Service URI is up before `main()` has run `DuskPlugin.install()`.
const Duration _kBootBudget = Duration(seconds: 180);
const Duration _kBootPollInterval = Duration(milliseconds: 500);

/// How long a launched emulator may take to report `sys.boot_completed`;
/// `adb wait-for-device` returns long before the system can install.
const Duration _kBootCompletedBudget = Duration(seconds: 180);
const Duration _kBootCompletedPollInterval = Duration(seconds: 2);

/// How long a process's output may keep arriving after it exited.
const Duration _kPipeGrace = Duration(seconds: 5);

/// Where `flutter build apk --profile` writes the APK, from the project root.
const String _kProfileApk = 'build/app/outputs/flutter-apk/app-profile.apk';

/// The `flutter run` device ids that build for a browser. A copy of artisan's
/// `StartCommand.browserDevices`, which no published artisan has yet.
const Set<String> _kBrowserDevices = <String>{'chrome', 'edge', 'web-server'};

/// What an `applicationId` must look like before it reaches `adb shell`,
/// whose arguments the device's `sh` reads again.
final RegExp _kDeviceShellWord = RegExp(r'^[A-Za-z0-9_.]+$');

/// Everything a campaign drives outside itself: host processes, artisan's
/// session and a connection to the started app. The production host runs
/// artisan's own commands in-process; a test records the calls.
abstract interface class PerfCampaignHost {
  /// Runs [executable] with [arguments] as an argv, never through a shell of
  /// its own, with [environment] as its whole environment: nothing is
  /// inherited on top of it.
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required Map<String, String> environment,
  });

  /// artisan's session state for this project, null when none is recorded.
  Future<Map<String, dynamic>?> readSession();

  /// The session's `flutter-dev.log`, null when there is none.
  Future<String?> readSessionLog();

  /// artisan's `stop`: signals the app and deletes the session state.
  Future<int> stop(ArtisanOutput output);

  /// artisan's `start` with [options] as its parsed flags.
  Future<int> start(Map<String, dynamic> options, ArtisanOutput output);

  /// Whether a process with [pid] still runs.
  bool isAlive(int pid);

  /// Whether [port] can be bound on loopback.
  Future<bool> isPortFree(int port);

  /// Waits [duration] between two polls.
  Future<void> pause(Duration duration);

  /// Connects to the VM Service at [vmServiceUri].
  Future<PerfCampaignApp> connect(String vmServiceUri);
}

/// The app one cold start brought up.
abstract interface class PerfCampaignApp {
  /// The id `ext.dusk.boot_id` answers; throws while the app is not there.
  Future<String> bootId();

  /// The driver an attempt drives the app with: `after_start` first, then
  /// `dusk:perf_run`. Opened once per attempt; the caller closes it.
  Future<(PerfRunDriver, PerfRunEnvironment)> driver(PerfPlatform platform);

  /// `dusk:perf_run` in-process, with [options] as its parsed flags, on the
  /// [driver] and [environment] the attempt opened; it leaves both open.
  Future<int> perfRun(
    Map<String, dynamic> options,
    ArtisanOutput output, {
    required PerfRunDriver driver,
    required PerfRunEnvironment environment,
  });

  /// Closes the VM Service connection; the app keeps running.
  Future<void> close();
}

/// Runs a whole perf campaign, one cold start per scenario attempt:
///
/// ```text
/// artisan dusk:perf_campaign <campaign.yaml> --platform=<chrome|android|ios>
///   [--label=run] [--out=build/perf] [--only=<substring>] [--device=<id>]
///   [--cdp-port=9222] [--timing] [--semantics-pass] [--json]
/// ```
///
/// Order: the platform and `--only` filter (nothing runs when it selects
/// nothing), `hooks.before_campaign`, `flutter pub get`, the Android
/// preparation, then per scenario up to `retries + 1` attempts of
/// `hooks.before_scenario`, artisan stop, a wait for the old app's pid and
/// ports, artisan start, the boot id, `after_start` and `dusk:perf_run`. A
/// hook, `pub get` or preparation step that fails stops the campaign; an
/// attempt that fails, however it fails, is recorded in
/// `<out>/<scenario>-<label>.err` and the campaign goes on. The app is
/// stopped at the end, then `hooks.after_campaign` runs once, however the
/// campaign ended. The exit code is 1 when any scenario failed, the
/// campaign stopped, or the final stop or `after_campaign` failed.
///
/// Everything printed, every `.err`, every run file and the `--json`
/// envelope are masked for the secrets the campaign loaded. A process that
/// cannot start stops the campaign like one that fails. Hooks run verbatim
/// through `/bin/sh -c` with `DUSK_PERF_PLATFORM`, `DUSK_PERF_LABEL`,
/// `DUSK_PERF_OUT` (and `DUSK_PERF_SCENARIO` before a scenario,
/// `DUSK_PERF_STATUS` after the campaign) on top of the inherited
/// environment. Hooks and preparation processes inherit it minus every
/// variable the campaign read through `${env.NAME}`; artisan start and stop
/// run in-process and have no such seam, so the `flutter run`, the Chrome
/// and the `adb force-stop` they spawn inherit the dispatcher's environment
/// whole.
///
/// The command runs inside the compiled dispatcher, so a dispatcher built
/// before a dusk change is the caller's to rebuild (`rm -f
/// .artisan/build.stamp` before invoking).
class DuskPerfCampaignCommand extends ArtisanCommand {
  DuskPerfCampaignCommand({
    PerfCampaignHost? host,
    Map<String, String>? environment,
  })  : _host = host ?? _ArtisanPerfCampaignHost(),
        _environment = environment;

  final PerfCampaignHost _host;

  /// The environment `${env.*}` and the hooks read; the process's own when
  /// null.
  final Map<String, String>? _environment;

  @override
  String get name => 'dusk:perf_campaign';

  @override
  String get description =>
      'Run every scenario of a perf campaign on one platform, each from a '
      'cold start, and summarise which passed.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  void configure(ArgParser parser) {
    addJsonFlag(parser);
    parser
      ..addOption(
        'campaign',
        help: 'The campaign YAML (or the first argument).',
      )
      ..addOption(
        'platform',
        help: 'The platform to run on; only scenarios listing it run.',
        allowed: PerfPlatform.values.map((PerfPlatform p) => p.name),
      )
      ..addOption(
        'label',
        help: 'Names this run in every file name; [a-z0-9_-] only.',
        defaultsTo: 'run',
      )
      ..addOption(
        'out',
        help: 'Directory the run and .err files are written to.',
        defaultsTo: 'build/perf',
      )
      ..addOption(
        'only',
        help: 'Runs only the scenarios whose name contains this substring.',
      )
      ..addOption(
        'device',
        help: 'The device to start on: required on ios (a USB device), an '
            'adb serial on android (default: the emulator running '
            'android.avd when set, else the first emulator).',
      )
      ..addOption(
        'cdp-port',
        help: 'Chrome DevTools port artisan start opens (chrome only).',
        defaultsTo: '9222',
      )
      ..addFlag(
        'timing',
        help: 'Passed to dusk:perf_run: also run timing-mode repeats.',
        defaultsTo: false,
      )
      ..addFlag(
        'semantics-pass',
        help: 'Passed to dusk:perf_run: also replay with semantics released.',
        defaultsTo: false,
      );
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Every input is validated before anything runs.
    final String? path =
        ctx.input.argument(0) ?? ctx.input.option('campaign') as String?;
    if (path == null || path.isEmpty) {
      ctx.output.error(
        'Usage: dusk:perf_campaign <campaign.yaml> '
        '--platform=<chrome|android|ios>: pass the campaign file.',
      );
      return 1;
    }
    final Object? platformName = ctx.input.option('platform');
    final PerfPlatform? platform = PerfPlatform.tryParse(platformName);
    if (platform == null) {
      ctx.output.error(
        platformName == null
            ? '--platform is required: pass chrome, android or ios.'
            : '--platform "$platformName" is not one of chrome, android, ios.',
      );
      return 1;
    }
    final String label = (ctx.input.option('label') as String?) ?? 'run';
    if (!isSafePerfName(label)) {
      ctx.output.error(
        '--label "$label" must use [a-z0-9_-] only: it becomes part of the '
        'file names.',
      );
      return 1;
    }
    final String? device = ctx.input.option('device') as String?;
    if (platform == PerfPlatform.ios && (device == null || device.isEmpty)) {
      ctx.output.error(
        '--platform=ios needs --device=<id> of a USB-connected device '
        '(`flutter devices` lists it): a profile build is not discovered '
        'over Wi-Fi reliably.',
      );
      return 1;
    }
    final Object? rawCdpPort = ctx.input.option('cdp-port') ?? '9222';
    final int? cdpPort = switch (rawCdpPort) {
      final int value => value,
      final String value => int.tryParse(value),
      _ => null,
    };
    if (cdpPort == null || cdpPort < 1 || cdpPort > 65535) {
      ctx.output.error('--cdp-port "$rawCdpPort" must be a port, 1 to 65535.');
      return 1;
    }

    // 2. The campaign, then a redactor for everything printed from here on.
    final Map<String, String> env = _environment ?? Platform.environment;
    final PerfCampaign campaign;
    try {
      campaign = await loadPerfCampaign(path, env: env);
    } on PerfCampaignException catch (e) {
      ctx.output.error('$path: $e');
      return 1;
    } on FileSystemException catch (e) {
      ctx.output.error('Cannot read campaign $path: ${e.message}');
      return 1;
    }
    final PerfRedactor redactor = PerfRedactor(campaign.secrets);
    final ArtisanOutput output = RedactingOutput(ctx.output, redactor);

    // 3. The filter comes before any hook or process: a campaign that would
    //    run nothing must not bring services up for it.
    final String? only = ctx.input.option('only') as String?;
    final List<PerfCampaignScenario> selected = <PerfCampaignScenario>[
      for (final PerfCampaignScenario s in campaign.scenarios)
        if (s.platforms.contains(platform) &&
            (only == null || s.scenario.name.contains(only)))
          s,
    ];
    if (selected.isEmpty) {
      output.error(
        only == null
            ? 'No scenario lists ${platform.name}.'
            : 'No scenario matched --only=$only on ${platform.name}.',
      );
      return 1;
    }

    return _CampaignRun(
      host: _host,
      env: env,
      inherited: <String, String>{
        for (final MapEntry<String, String>(:String key, :String value)
            in env.entries)
          if (!campaign.secretEnvNames.contains(key)) key: value,
      },
      redactor: redactor,
      output: output,
      envelopeOutput: ctx.output,
      platform: platform,
      label: label,
      out: (ctx.input.option('out') as String?) ?? 'build/perf',
      device: device,
      cdpPort: '$cdpPort',
      timing: perfReadBool(ctx.input.option('timing')),
      semanticsPass: perfReadBool(ctx.input.option('semantics-pass')),
      json: wantsJson(ctx),
    ).run(campaign, selected);
  }
}

// ---------------------------------------------------------------------------
// The run
// ---------------------------------------------------------------------------

/// A step before the first scenario that failed: the campaign stops there.
final class _CampaignStop implements Exception {
  _CampaignStop(this.message, [this.detail]);

  /// The sentence printed.
  final String message;

  /// What the failed process printed, for `campaign-<label>.err`.
  final String? detail;
}

/// How far one attempt got, for what its `.err` quotes.
enum _Phase { stopping, starting, running }

/// The phase an attempt has reached, readable after it throws.
final class _Progress {
  _Phase phase = _Phase.stopping;
}

/// Where a scenario ended, as the `--json` envelope spells it.
enum _Status {
  ok('ok'),
  failed('failed'),

  /// Never attempted: the campaign stopped before it.
  notRun('not_run');

  const _Status(this.wire);

  final String wire;
}

/// One scenario's outcome, as the summary and the envelope report it.
final class _ScenarioResult {
  const _ScenarioResult({
    required this.name,
    required this.status,
    required this.attempts,
    this.runFile,
    this.errFile,
    this.stop,
  });

  /// A scenario the campaign stopped before.
  const _ScenarioResult.notRun(this.name)
      : status = _Status.notRun,
        attempts = 0,
        runFile = null,
        errFile = null,
        stop = null;

  final String name;
  final _Status status;
  final int attempts;

  bool get ok => status == _Status.ok;
  final String? runFile;
  final String? errFile;

  /// Why the campaign stops at this scenario, or null to go on.
  final String? stop;

  /// The summary's word for it: a pass on a later attempt names that attempt
  /// and the `.err` that holds the earlier ones.
  String get line => switch ((status, attempts)) {
        (_Status.failed, _) => 'FAILED (see $errFile)',
        (_Status.notRun, _) => 'not run',
        (_Status.ok, 1) => 'ok',
        (_Status.ok, _) => 'ok (attempt $attempts, see $errFile)',
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'scenario': name,
        'status': status.wire,
        'attempts': attempts,
        'runFile': runFile,
        'errFile': errFile,
      };
}

/// One invocation of the campaign, holding its settings.
final class _CampaignRun {
  _CampaignRun({
    required this.host,
    required this.env,
    required this.inherited,
    required this.redactor,
    required this.output,
    required this.envelopeOutput,
    required this.platform,
    required this.label,
    required this.out,
    required this.device,
    required this.cdpPort,
    required this.timing,
    required this.semanticsPass,
    required this.json,
  })  : cwd = Directory.current.path,
        projectRoot = StateFile.projectRootFor(Directory.current.path);

  final PerfCampaignHost host;
  final Map<String, String> env;

  /// What a hook or a preparation process inherits: [env] minus every
  /// variable the campaign read through `${env.NAME}`, so a credential the
  /// campaign consumes never reaches a server a hook leaves running.
  final Map<String, String> inherited;
  final PerfRedactor redactor;
  final ArtisanOutput output;

  /// The unwrapped output the `--json` envelope is written to, once, after
  /// [PerfRedactor.redactJson]: [output]'s text pass could rewrite a number
  /// a secret matches into invalid JSON.
  final ArtisanOutput envelopeOutput;
  final PerfPlatform platform;
  final String label;
  final String out;
  final String? device;
  final String cdpPort;
  final bool timing;
  final bool semanticsPass;
  final bool json;

  /// Where the command was invoked from: the hooks run there.
  final String cwd;

  /// The package artisan starts, where flutter and the APK path resolve.
  final String projectRoot;

  /// Whether any attempt reached artisan start, so the end has an app to stop.
  bool _started = false;

  Future<int> run(
    PerfCampaign campaign,
    List<PerfCampaignScenario> scenarios,
  ) async {
    final List<_ScenarioResult> results = <_ScenarioResult>[];

    // Why the campaign stopped before its last scenario, or null.
    String? stopped;

    // What went wrong after the scenarios, each a sentence of its own.
    final List<String> errors = <String>[];

    final File campaignErr = _errFile('campaign');
    final StringBuffer campaignRecord = StringBuffer();

    // Set once steps 1 and 2 ran to their end; an exception that escapes
    // them still gets the teardown below, reported as failed, and then
    // propagates.
    bool finished = false;
    try {
      // 1. Everything before the first scenario; a failure stops the
      //    campaign.
      await _clear(campaignErr);
      String? target;
      try {
        target = await _prepare(campaign);
      } on _CampaignStop catch (stop) {
        final String? detail = stop.detail;
        if (detail != null) campaignRecord.write('${stop.message}\n$detail');
        stopped = detail != null &&
                await _record(campaignErr, campaignRecord.toString())
            ? '${stop.message}; see ${campaignErr.path}'
            : stop.message;
      }

      // 2. The scenarios, each one's line printed as it finishes, then the
      //    app stopped whatever happened.
      if (target != null) {
        final int width = scenarios
            .map((PerfCampaignScenario s) => s.scenario.name.length)
            .reduce((int a, int b) => a > b ? a : b);
        try {
          for (final PerfCampaignScenario scenario in scenarios) {
            final _ScenarioResult result =
                await _scenario(scenario, campaign, target);
            results.add(result);
            if (!json) {
              output
                  .writeln('  ${result.name.padRight(width)}  ${result.line}');
            }
            stopped = result.stop;
            if (stopped != null) break;
          }
        } finally {
          if (_started) {
            final int code = await host.stop(BufferedOutput());
            if (code != 0) {
              errors.add('artisan stop exited $code after the campaign; the '
                  'app may still be running.');
            }
          }
        }
      }
      finished = true;
    } finally {
      // 3. The teardown, once, however the campaign ended: a failed
      //    before_campaign may have started half of what it tears down.
      final String? teardown = campaign.hooks.afterCampaign;
      if (teardown != null) {
        final bool ok = finished &&
            stopped == null &&
            errors.isEmpty &&
            results.every((_ScenarioResult r) => r.ok);
        final String? failure = await _afterCampaign(
          teardown,
          ok: ok,
          err: campaignErr,
          record: campaignRecord,
        );
        if (failure != null) errors.add(failure);
      }
    }

    // 4. The report: every selected scenario, those a stop left untried
    //    included, so a caller of `--json` always gets the envelope.
    final List<_ScenarioResult> reported = <_ScenarioResult>[
      ...results,
      for (final PerfCampaignScenario s in scenarios.skip(results.length))
        _ScenarioResult.notRun(s.scenario.name),
    ];
    if (json) {
      envelopeOutput.writeln(
        jsonEncode(
          redactor.redactJson(<String, Object?>{
            'results': <Object?>[
              for (final _ScenarioResult r in reported) r.toJson(),
            ],
            if (stopped != null) 'stopped': stopped,
            if (errors.isNotEmpty) 'errors': errors,
          }),
        ),
      );
    }
    errors.forEach(output.error);
    if (stopped != null) {
      output.error('Campaign stopped: $stopped.');
      return 1;
    }
    final int failed = results.where((_ScenarioResult r) => !r.ok).length;
    if (failed > 0) {
      output.error('$failed of ${results.length} scenarios failed; each '
          'FAILED line names its .err.');
      return 1;
    }
    if (errors.isNotEmpty) return 1;
    if (!json) {
      output.success('Campaign done: ${results.length} scenarios on '
          '${platform.name}, run files in $out.');
    }
    return 0;
  }

  /// Runs `before_campaign`, `flutter pub get` and the platform's
  /// preparation; answers the device artisan start targets. Throws
  /// [_CampaignStop].
  Future<String> _prepare(PerfCampaign campaign) async {
    // 1. The app's services, before anything else touches the project.
    final String? hook = campaign.hooks.beforeCampaign;
    if (hook != null) {
      final ProcessResult result = await _hook(hook);
      if (result.exitCode != 0) {
        throw _CampaignStop(
          'hooks.before_campaign exited ${result.exitCode}',
          _processText(result),
        );
      }
    }

    // 2. An edit to pubspec_overrides.yaml does not reach
    //    .dart_tool/package_config.json on its own, and a campaign once
    //    measured the old checkout of a repointed override.
    await _step('flutter', <String>['pub', 'get']);

    // 3. The device.
    return switch (platform) {
      PerfPlatform.chrome => device ?? 'chrome',
      PerfPlatform.ios => device!,
      PerfPlatform.android => await _prepareAndroid(campaign.android),
    };
  }

  /// Boots, reverses, installs and grants as [android] asks; answers the
  /// serial. Throws [_CampaignStop].
  Future<String> _prepareAndroid(PerfAndroid android) async {
    // 1. Refuse a grant with nothing to grant it to before a long boot.
    String? applicationId;
    if (android.grant.isNotEmpty) {
      applicationId = _androidApplicationId(projectRoot);
      if (applicationId == null) {
        throw _CampaignStop(
          'android.grant needs the app\'s applicationId, and '
          '$projectRoot/android/app/build.gradle(.kts) declares none.',
        );
      }
      if (!_kDeviceShellWord.hasMatch(applicationId)) {
        throw _CampaignStop(
          'the applicationId "$applicationId" read from '
          '$projectRoot/android/app/build.gradle(.kts) could not be used: '
          'pm grant runs in the device shell, so it must be letters, digits, '
          '_ and . only, and a Gradle expression in it is not resolved.',
        );
      }
    }

    // 2. The SDK's adb: flutter drives it, and a second adb of another
    //    version restarts the shared server whenever either runs, which
    //    kills `flutter run` before it prints the VM Service URI.
    final String adb = _adb();
    final String? avd = android.avd;
    final String serial = device ??
        (avd == null ? await _emulatorSerial(adb) : await _avdSerial(adb, avd));
    if (avd != null) await _awaitBootCompleted(adb, serial);

    // 3. The host ports the app dials, then a profile build installed and
    //    granted up front: a permission prompt on first launch sits on top
    //    of the task and swallows every later launch intent.
    for (final int port in android.reverse) {
      await _step(
        adb,
        <String>['-s', serial, 'reverse', 'tcp:$port', 'tcp:$port'],
      );
    }
    if (applicationId != null) {
      await _step('flutter', <String>['build', 'apk', '--profile']);
      await _step(adb, <String>['-s', serial, 'install', '-r', _kProfileApk]);
      for (final String permission in android.grant) {
        await _step(adb, <String>[
          '-s',
          serial,
          'shell',
          'pm',
          'grant',
          applicationId,
          permission,
        ]);
      }
    }
    return serial;
  }

  String _adb() {
    final String? home = env['ANDROID_HOME'];
    if (home != null && home.isNotEmpty) {
      final String sdkAdb = '$home/platform-tools/adb';
      if (File(sdkAdb).existsSync()) return sdkAdb;
    }
    return 'adb';
  }

  /// The first `emulator-*` serial `adb devices` lists as ready.
  Future<String> _emulatorSerial(String adb) async {
    final List<String> serials = await _emulatorSerials(adb);
    if (serials.isEmpty) {
      throw _CampaignStop(
        'adb devices lists no emulator that is ready: boot one, set '
        'android.avd, or pass --device=<serial>',
      );
    }
    return serials.first;
  }

  /// The serial of the emulator running [avd], launched first when none
  /// is. Matched by name rather than taken as the first emulator: another
  /// AVD already running would otherwise be the one measured, and `adb
  /// wait-for-device` returns at once for it.
  Future<String> _avdSerial(String adb, String avd) async {
    final String? running = await _runningAvd(adb, avd);
    if (running != null) return running;
    await _step('flutter', <String>['emulators', '--launch', avd]);
    final Stopwatch clock = Stopwatch()..start();
    final int maxPolls = _kBootCompletedBudget.inMilliseconds ~/
        _kBootCompletedPollInterval.inMilliseconds;
    for (int poll = 1;; poll++) {
      final String? serial = await _runningAvd(adb, avd);
      if (serial != null) return serial;
      if (poll >= maxPolls || clock.elapsed >= _kBootCompletedBudget) {
        throw _CampaignStop(
          'no emulator running $avd appeared in adb devices within '
          '${_kBootCompletedBudget.inSeconds} s of launching it',
        );
      }
      await host.pause(_kBootCompletedPollInterval);
    }
  }

  /// The ready emulator whose `adb emu avd name` is [avd], or null.
  Future<String?> _runningAvd(String adb, String avd) async {
    for (final String serial in await _emulatorSerials(adb)) {
      final ProcessResult result = await _spawn(
        adb,
        <String>['-s', serial, 'emu', 'avd', 'name'],
        workingDirectory: projectRoot,
        environment: inherited,
      );
      // The console answers the name, then `OK`, CRLF-separated.
      final String name = '${result.stdout}'.split('\n').first.trim();
      if (result.exitCode == 0 && name == avd) return serial;
    }
    return null;
  }

  /// Every `emulator-*` serial `adb devices` lists as ready, in its order.
  Future<List<String>> _emulatorSerials(String adb) async {
    final ProcessResult result = await _step(adb, <String>['devices']);
    return <String>[
      for (final RegExpMatch match
          in RegExp(r'^(emulator-\d+)\s+device\s*$', multiLine: true)
              .allMatches('${result.stdout}'))
        match.group(1)!,
    ];
  }

  /// Polls `sys.boot_completed` until it reads `1`. A non-zero exit is the
  /// device still coming up, not a failure.
  Future<void> _awaitBootCompleted(String adb, String serial) async {
    final Stopwatch clock = Stopwatch()..start();
    final int maxPolls = _kBootCompletedBudget.inMilliseconds ~/
        _kBootCompletedPollInterval.inMilliseconds;
    for (int poll = 1;; poll++) {
      final ProcessResult result = await _spawn(
        adb,
        <String>['-s', serial, 'shell', 'getprop', 'sys.boot_completed'],
        workingDirectory: projectRoot,
        environment: inherited,
      );
      if ('${result.stdout}'.trim() == '1') return;
      if (poll >= maxPolls || clock.elapsed >= _kBootCompletedBudget) {
        throw _CampaignStop(
          '$serial did not report sys.boot_completed=1 within '
          '${_kBootCompletedBudget.inSeconds} s',
        );
      }
      await host.pause(_kBootCompletedPollInterval);
    }
  }

  /// Runs one preparation process in the project root. Throws
  /// [_CampaignStop] with its output when it exits non-zero.
  Future<ProcessResult> _step(String executable, List<String> args) async {
    final ProcessResult result = await _spawn(
      executable,
      args,
      workingDirectory: projectRoot,
      environment: inherited,
    );
    if (result.exitCode != 0) {
      throw _CampaignStop(
        '${<String>[executable, ...args].join(' ')} exited '
        '${result.exitCode}',
        _processText(result),
      );
    }
    return result;
  }

  /// [PerfCampaignHost.run], with a process that cannot start at all (no
  /// such executable, no permission) turned into a [_CampaignStop].
  Future<ProcessResult> _spawn(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    try {
      return await host.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    } on ProcessException catch (e) {
      throw _CampaignStop('$executable could not start: ${e.message}');
    }
  }

  /// Runs [hook] verbatim: never interpolated, and no value of the campaign
  /// on its command line. [scenario] names the scenario it runs before,
  /// [status] how the campaign ended for `after_campaign`. Throws
  /// [_CampaignStop] when the shell cannot start.
  Future<ProcessResult> _hook(
    String hook, {
    String? scenario,
    String? status,
  }) =>
      _spawn(
        '/bin/sh',
        <String>['-c', hook],
        workingDirectory: cwd,
        environment: <String, String>{
          ...inherited,
          'DUSK_PERF_PLATFORM': platform.name,
          'DUSK_PERF_LABEL': label,
          'DUSK_PERF_OUT': out,
          if (scenario != null) 'DUSK_PERF_SCENARIO': scenario,
          if (status != null) 'DUSK_PERF_STATUS': status,
        },
      );

  /// Runs `hooks.after_campaign` with `DUSK_PERF_STATUS` `ok` or `failed`;
  /// answers the sentence to report when it failed, null when it exited 0.
  /// What a failed one printed is appended to [record] and written to [err].
  Future<String?> _afterCampaign(
    String hook, {
    required bool ok,
    required File err,
    required StringBuffer record,
  }) async {
    final ProcessResult result;
    try {
      result = await _hook(hook, status: ok ? 'ok' : 'failed');
    } on _CampaignStop catch (e) {
      return 'hooks.after_campaign could not run: ${e.message}';
    }
    if (result.exitCode == 0) return null;
    final String failure = 'hooks.after_campaign exited ${result.exitCode}';
    if (record.isNotEmpty) record.writeln();
    record.write('$failure\n${_processText(result)}');
    return await _record(err, record.toString())
        ? '$failure; see ${err.path}'
        : failure;
  }

  /// Up to `retries + 1` attempts of [scenario], each from a cold start.
  Future<_ScenarioResult> _scenario(
    PerfCampaignScenario scenario,
    PerfCampaign campaign,
    String target,
  ) async {
    final String name = scenario.scenario.name;
    final File err = _errFile(name);
    await _clear(err);
    final StringBuffer record = StringBuffer();
    final int attempts = campaign.retries + 1;

    for (int attempt = 1; attempt <= attempts; attempt++) {
      // 1. The app's per-scenario reset. A failing one stops the campaign:
      //    every scenario after it would run against the same broken state.
      final String? hook = campaign.hooks.beforeScenario;
      if (hook != null) {
        final ProcessResult result;
        try {
          result = await _hook(hook, scenario: name);
        } on _CampaignStop catch (e) {
          final String stop =
              'hooks.before_scenario could not run before $name: ${e.message}';
          record.writeln('=== $stop');
          await _record(err, record.toString());
          return _ScenarioResult(
            name: name,
            status: _Status.failed,
            attempts: attempt,
            errFile: err.path,
            stop: stop,
          );
        }
        if (result.exitCode != 0) {
          final String stop =
              'hooks.before_scenario exited ${result.exitCode} before $name';
          record
            ..writeln('=== $stop')
            ..write(_processText(result));
          await _record(err, record.toString());
          return _ScenarioResult(
            name: name,
            status: _Status.failed,
            attempts: attempt,
            errFile: err.path,
            stop: stop,
          );
        }
      }

      // 2. The attempt. This catch is the campaign's one catch-all: whatever
      //    an attempt throws is recorded and the campaign goes on.
      final BufferedOutput captured = BufferedOutput();
      final _Progress progress = _Progress();
      try {
        await _attempt(
          scenario,
          campaign.afterStart,
          target,
          captured,
          progress,
        );
        return _ScenarioResult(
          name: name,
          status: _Status.ok,
          attempts: attempt,
          runFile: _runFile(name).path,
          errFile: record.isEmpty ? null : err.path,
        );
      } catch (e, st) {
        record.writeln(
          '=== attempt $attempt of $attempts failed: '
          '${e is PerfRunException ? e.message : e}',
        );
        if (e is! PerfRunException) record.writeln(st);
        if (captured.content.isNotEmpty) {
          record
            ..writeln('--- output')
            ..write(captured.content);
        }
        if (progress.phase == _Phase.starting) {
          final String? log = await host.readSessionLog();
          if (log != null) {
            record
              ..writeln('--- flutter-dev.log')
              ..write(log);
          }
        }
        await _record(err, record.toString());
      }
    }
    return _ScenarioResult(
      name: name,
      status: _Status.failed,
      attempts: attempts,
      errFile: err.path,
    );
  }

  /// One cold start and one `dusk:perf_run`; throws on anything that stops
  /// it. [progress] tracks how far it got.
  Future<void> _attempt(
    PerfCampaignScenario scenario,
    List<PerfSetupStep> afterStart,
    String target,
    BufferedOutput captured,
    _Progress progress,
  ) async {
    // 1. Stop what runs and wait until it is gone. The session is read
    //    first because stop deletes it, and start fails at once on a port
    //    the old app still holds.
    final Map<String, dynamic>? previous = await host.readSession();
    final int stopped = await host.stop(captured);
    if (stopped != 0) throw PerfRunException('artisan stop exited $stopped');
    if (previous != null) await _awaitGone(previous);

    // 2. Start and wait for dusk to answer: the VM Service is up before
    //    `main()` has installed dusk.
    progress.phase = _Phase.starting;
    _started = true;
    final int started = await host.start(_startOptions(target), captured);
    if (started != 0) throw PerfRunException('artisan start exited $started');
    final Object? uri = (await host.readSession())?['vmServiceUri'];
    if (uri is! String) {
      throw PerfRunException('artisan start recorded no vmServiceUri');
    }
    final PerfCampaignApp app = await host.connect(uri);
    try {
      await pollDuskBoot(
        app.bootId,
        replacing: null,
        timeout: _kBootBudget,
        pollInterval: _kBootPollInterval,
        pause: host.pause,
        failure: 'the app did not answer ext.dusk.boot_id within '
            '${_kBootBudget.inSeconds} s of the start',
      );
      progress.phase = _Phase.running;

      // 3. One driver for the attempt: after_start and perf_run share it, so
      //    the host is described and the run log read once.
      final (PerfRunDriver driver, PerfRunEnvironment env) =
          await app.driver(platform);
      try {
        // 4. The campaign's setup, the Router first: boot_id answers before
        //    the app has mounted one, and a login screen needs it.
        final String name = scenario.scenario.name;
        if (afterStart.isNotEmpty) {
          final PerfSetupRunner runner =
              PerfSetupRunner(PerfActions(driver, env), redactor: redactor);
          await runner.awaitRouter(name, budget: _routerBudget(afterStart));
          await runner.run(afterStart, name);
        }

        // 5. The measured run.
        final int code = await app.perfRun(
          _perfRunOptions(scenario),
          captured,
          driver: driver,
          environment: env,
        );
        if (code != 0) throw PerfRunException('dusk:perf_run exited $code');
        await _maskRunFile(_runFile(name));
      } finally {
        await driver.close();
      }
    } finally {
      await app.close();
    }
  }

  /// Masks [file] for every secret the campaign holds. perf_run masks it for
  /// its own scenario's secrets only, and an app exception it records can
  /// quote an `after_start` credential. Masked as a tree, so it stays valid
  /// JSON with the same keys and numbers.
  Future<void> _maskRunFile(File file) async {
    final Object? run = jsonDecode(await file.readAsString());
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(redactor.redactJson(run)),
    );
  }

  /// Polls until [previous]'s pid is gone and its ports are free. Throws
  /// [PerfRunException] after [_kStopBudget].
  Future<void> _awaitGone(Map<String, dynamic> previous) async {
    final int? pid = previous['pid'] as int?;
    final int? cdp = previous['cdpPort'] as int?;
    final bool browser =
        cdp != null || _kBrowserDevices.contains(previous['device']);
    // The ports artisan start refuses to start on: the web port (recorded on
    // every session, bound only by a browser build) and the CDP port. Not the
    // VM Service port: on Android `adb forward` keeps listening on it after
    // the app is gone, for as long as the adb server lives, and flutter
    // starts over it regardless.
    final List<int> ports = <int>[
      if (browser && previous['webPort'] is int) previous['webPort'] as int,
      if (cdp != null) cdp,
    ];
    final Stopwatch clock = Stopwatch()..start();
    final int maxPolls =
        _kStopBudget.inMilliseconds ~/ _kStopPollInterval.inMilliseconds;
    for (int poll = 1;; poll++) {
      final bool alive = pid != null && host.isAlive(pid);
      final List<int> held = <int>[
        for (final int port in ports)
          if (!await host.isPortFree(port)) port,
      ];
      if (!alive && held.isEmpty) return;
      if (poll >= maxPolls || clock.elapsed >= _kStopBudget) {
        throw PerfRunException(
          '${_kStopBudget.inSeconds} s after artisan stop the previous app '
          '${alive ? 'is still running (pid $pid)' : 'has exited'}'
          '${held.isEmpty ? '' : ' and port ${held.join(', ')} is still held'}'
          ', so a start would fail on it.',
        );
      }
      await host.pause(_kStopPollInterval);
    }
  }

  /// artisan start's options, typed as its `handle` casts them.
  Map<String, dynamic> _startOptions(String target) => <String, dynamic>{
        'device': target,
        if (platform == PerfPlatform.chrome) 'cdp-port': cdpPort,
        // `--profile` on a device (artisan passes it on no browser target).
        'profile-static': platform != PerfPlatform.chrome,
        'flutter-arg': <String>[],
      };

  /// dusk:perf_run's options. Its own `--json` stays off: what it prints is
  /// captured for the `.err`, where the summary reads better.
  Map<String, dynamic> _perfRunOptions(PerfCampaignScenario scenario) =>
      <String, dynamic>{
        'scenario': scenario.path,
        'variant': scenario.variant,
        'label': label,
        'out': out,
        'platform': platform.name,
        'timing': timing,
        'semantics-pass': semanticsPass,
        'json': false,
      };

  File _errFile(String name) => File('$out/$name-$label.err').absolute;

  /// The file perf_run writes for the scenario [name].
  File _runFile(String name) => File('$out/$name-$label.json').absolute;

  /// Removes a previous campaign's `.err`, which a `see <path>` would
  /// otherwise point at. One that cannot be removed is said through
  /// [output] and the campaign goes on, as [_record] does for a write.
  Future<void> _clear(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException catch (e) {
      output.error('dusk:perf_campaign could not delete ${file.path}: '
          '${e.osError?.message ?? e.message}.');
    }
  }

  /// Writes [text], masked, to [file]; answers whether it could. A file
  /// that cannot be written is said through [output] and the campaign goes
  /// on: a full disk or an unwritable `--out` must not cost the scenarios
  /// after it, nor the app stop at the end.
  Future<bool> _record(File file, String text) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(redactor.redact(text));
      return true;
    } on FileSystemException catch (e) {
      output.error('dusk:perf_campaign could not write ${file.path}: '
          '${e.osError?.message ?? e.message}.');
      return false;
    }
  }
}

String _processText(ProcessResult result) => '${result.stdout}${result.stderr}';

/// Reads a process's [stdout] and [stderr] until both close, waiting for the
/// [exitCode] and then at most [grace] more: a hook that backgrounds a server
/// without redirecting it leaves that server holding the pipes for as long as
/// it lives. Output still open after the grace is cut, and the cut is said in
/// `stderr`. Malformed bytes decode to U+FFFD rather than throwing: a byte
/// that arrives after the cut would raise where nothing listens.
Future<({int exitCode, String stdout, String stderr})> drainProcessOutput({
  required Stream<List<int>> stdout,
  required Stream<List<int>> stderr,
  required Future<int> exitCode,
  required Duration grace,
  String executable = 'the process',
}) async {
  final StringBuffer out = StringBuffer();
  final StringBuffer err = StringBuffer();
  const Utf8Decoder decoder = Utf8Decoder(allowMalformed: true);
  final StreamSubscription<String> outSub =
      stdout.transform(decoder).listen(out.write);
  final StreamSubscription<String> errSub =
      stderr.transform(decoder).listen(err.write);
  // Taken now, not after the exit: `asFuture` replaces the done handler, and
  // one set after a short-lived process already closed its pipes never
  // completes, which cut every hook at the grace and blamed a server.
  // The failure is held as a value, so a pipe that errors before the exit
  // code arrives never becomes an unhandled error that ends the campaign.
  final Future<Object?> closed = Future.wait(
    <Future<void>>[outSub.asFuture<void>(), errSub.asFuture<void>()],
    eagerError: true,
  ).then<Object?>((_) => null, onError: (Object error) => error);
  final int code = await exitCode;
  try {
    final Object? failure = await closed.timeout(grace);
    if (failure != null) {
      await Future.wait(<Future<void>>[outSub.cancel(), errSub.cancel()]);
      err.writeln(
        '\n[dusk:perf_campaign] reading the output of $executable failed: '
        '$failure',
      );
    }
  } on TimeoutException {
    await Future.wait(<Future<void>>[outSub.cancel(), errSub.cancel()]);
    err.writeln(
      '\n[dusk:perf_campaign] $executable exited $code, but a process it '
      'left running still holds its stdout or stderr; output after the exit '
      'is not shown. Redirect a background server\'s output '
      '(`cmd >log 2>&1 </dev/null &`).',
    );
  }
  return (exitCode: code, stdout: '$out', stderr: '$err');
}

/// How long `after_start` waits for the app to mount a Router: the largest
/// `timeout_ms` among its guards, the guard default when it has none, never
/// less than perf_run's own [kPerfRouterBudget]. A login guard written to
/// wait out a slow cold start must not lose to a router wait that gives up
/// first.
Duration _routerBudget(List<PerfSetupStep> afterStart) {
  int ms = 0;
  for (final PerfSetupStep step in afterStart) {
    for (PerfSetupGuard? g = step.guard; g != null; g = g.parent) {
      if (g.timeoutMs > ms) ms = g.timeoutMs;
    }
  }
  final Duration guards =
      Duration(milliseconds: ms == 0 ? kPerfWhenTimeoutMs : ms);
  return guards > kPerfRouterBudget ? guards : kPerfRouterBudget;
}

/// The first `applicationId` in the Android app module's Gradle file under
/// [projectRoot], or null. The same lookup as artisan's
/// `StopCommand.androidApplicationId`, which is `@visibleForTesting` there.
String? _androidApplicationId(String projectRoot) {
  final RegExp pattern = RegExp('applicationId\\s*=?\\s*["\']([^"\']+)["\']');
  for (final String file in <String>['build.gradle', 'build.gradle.kts']) {
    final File gradle = File('$projectRoot/android/app/$file');
    if (!gradle.existsSync()) continue;
    final RegExpMatch? match = pattern.firstMatch(gradle.readAsStringSync());
    if (match != null) return match.group(1);
  }
  return null;
}

// ---------------------------------------------------------------------------
// The artisan host
// ---------------------------------------------------------------------------

/// Runs artisan's stop and start in-process, as `RestartCommand` chains
/// them, and connects to the started app over its VM Service.
final class _ArtisanPerfCampaignHost implements PerfCampaignHost {
  /// Waits for the process to exit, not for its pipes to close: a hook that
  /// backgrounds a server without redirecting it (`cmd &`) leaves that
  /// server holding stdout, and `Process.run` would wait on it for as long
  /// as the server lives. Output still arriving [_kPipeGrace] after the exit
  /// is cut, and the cut is said in the output.
  @override
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
    );
    final ({int exitCode, String stdout, String stderr}) drained =
        await drainProcessOutput(
      stdout: process.stdout,
      stderr: process.stderr,
      exitCode: process.exitCode,
      grace: _kPipeGrace,
      executable: executable,
    );
    return ProcessResult(
      process.pid,
      drained.exitCode,
      drained.stdout,
      drained.stderr,
    );
  }

  @override
  Future<Map<String, dynamic>?> readSession() => StateFile.read();

  /// Decoded leniently: the log is flutter's and the app's raw output, and
  /// a malformed byte in it must not throw out of the attempt's catch.
  @override
  Future<String?> readSessionLog() async {
    final File log =
        File('${File(StateFile.path).parent.path}/flutter-dev.log');
    if (!log.existsSync()) return null;
    return const Utf8Decoder(allowMalformed: true)
        .convert(await log.readAsBytes());
  }

  @override
  Future<int> stop(ArtisanOutput output) => StopCommand().handle(
        ArtisanContext.bare(MapInput(const <String, dynamic>{}), output),
      );

  @override
  Future<int> start(Map<String, dynamic> options, ArtisanOutput output) =>
      StartCommand().handle(ArtisanContext.bare(MapInput(options), output));

  @override
  bool isAlive(int pid) => processAlive(pid);

  @override
  Future<bool> isPortFree(int port) async {
    try {
      final ServerSocket socket =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  @override
  Future<void> pause(Duration duration) => Future<void>.delayed(duration);

  @override
  Future<PerfCampaignApp> connect(String vmServiceUri) async {
    final VmServiceClient client = VmServiceClient(vmServiceUri);
    await client.connect();
    return _ArtisanPerfCampaignApp(client);
  }
}

/// The started app, driven through one VM Service connection.
final class _ArtisanPerfCampaignApp implements PerfCampaignApp {
  _ArtisanPerfCampaignApp(this._client);

  final VmServiceClient _client;

  @override
  Future<String> bootId() => readDuskBootId(_client);

  @override
  Future<(PerfRunDriver, PerfRunEnvironment)> driver(PerfPlatform platform) =>
      connectArtisanPerfRun(
        ArtisanContext.connected(
          MapInput(const <String, dynamic>{}),
          BufferedOutput(),
          _client,
        ),
        platform,
      );

  @override
  Future<int> perfRun(
    Map<String, dynamic> options,
    ArtisanOutput output, {
    required PerfRunDriver driver,
    required PerfRunEnvironment environment,
  }) =>
      DuskPerfRunCommand.connected(driver, environment).handle(
        ArtisanContext.connected(MapInput(options), output, _client),
      );

  @override
  Future<void> close() => _client.disconnect();
}
