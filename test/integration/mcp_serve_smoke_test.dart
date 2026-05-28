@Tags(<String>['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Integration smoke test for `dart run fluttersdk_dusk mcp:serve`.
///
/// Exercises the full stdio JSON-RPC boot path and asserts that the 31
/// `dusk_*` MCP tools are advertised via `tools/list`.
///
/// Skipped by default. Tagged `integration` so the manual invocation opts in:
///
/// ```
/// flutter test test/integration/mcp_serve_smoke_test.dart --tags=integration
/// ```
///
/// **TDD red phase**: this test currently FAILS because `bin/fluttersdk_dusk.dart`
/// calls `runArtisan` without `collectMcpTools: true`. Step 2.3 will add that
/// flag and turn this green.
void main() {
  // Resolve sibling package paths relative to the dusk package root.
  // `Directory.current` inside a `flutter test` run is the package root.
  final String duskRoot = Directory.current.absolute.path;
  final String referencesRoot = Directory(duskRoot).parent.absolute.path;
  final String artisanPath = '$referencesRoot/fluttersdk_artisan';
  final String contractsPath =
      '$referencesRoot/fluttersdk_wind_diagnostics_contracts';

  late Directory tempDir;
  late Process mcpProcess;

  setUpAll(() async {
    // 1. Create a minimal consumer project that depends on the local dusk package.
    tempDir = await Directory.systemTemp.createTemp('dusk_mcp_smoke_');

    final String pubspecYaml = '''
name: dusk_mcp_smoke
description: dusk mcp:serve smoke test fixture
publish_to: 'none'

environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: '>=3.22.0'

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  fluttersdk_dusk:
    path: $duskRoot

dependency_overrides:
  fluttersdk_artisan:
    path: $artisanPath
  fluttersdk_wind_diagnostics_contracts:
    path: $contractsPath
''';

    await File('${tempDir.path}/pubspec.yaml').writeAsString(pubspecYaml);

    // 2. Resolve pub dependencies so the `dart run` below can locate packages.
    final ProcessResult pubGet = await Process.run(
      'flutter',
      <String>['pub', 'get'],
      workingDirectory: tempDir.path,
    ).timeout(const Duration(seconds: 60));

    if (pubGet.exitCode != 0) {
      throw StateError(
        'flutter pub get failed in temp consumer dir.\n'
        'stdout: ${pubGet.stdout}\nstderr: ${pubGet.stderr}',
      );
    }

    // 3. Spawn `dart run fluttersdk_dusk mcp:serve` as a long-lived subprocess.
    //    stdin is piped so we can send JSON-RPC requests.
    mcpProcess = await Process.start(
      'dart',
      <String>['run', 'fluttersdk_dusk', 'mcp:serve'],
      workingDirectory: tempDir.path,
    );
  });

  tearDownAll(() async {
    // Kill the mcp:serve subprocess and remove the temp dir.
    mcpProcess.kill(ProcessSignal.sigterm);
    await mcpProcess.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        mcpProcess.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    await tempDir.delete(recursive: true);
  });

  test(
    'mcp:serve advertises exactly 31 dusk_* tools via tools/list',
    () async {
      // Collect stdout lines concurrently to avoid pipe backpressure deadlock.
      final List<String> stdoutLines = <String>[];
      final Completer<void> stdoutDone = Completer<void>();

      mcpProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            stdoutLines.add,
            onDone: () {
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
          );

      // Drain stderr so the pipe never blocks the server.
      mcpProcess.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) {});

      // 1. Send MCP initialize handshake.
      const String initialize = '{"jsonrpc":"2.0","id":1,"method":"initialize",'
          '"params":{"protocolVersion":"2024-11-05","capabilities":{},'
          '"clientInfo":{"name":"smoke","version":"0"}}}';
      mcpProcess.stdin.writeln(initialize);
      await mcpProcess.stdin.flush();

      // 2. Give the server 5s to process initialize before sending tools/list.
      await Future<void>.delayed(const Duration(seconds: 5));

      // 3. Send tools/list request.
      const String toolsList =
          '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}';
      mcpProcess.stdin.writeln(toolsList);
      await mcpProcess.stdin.flush();

      // 4. Wait up to 20s for the tools/list response (id=2) to appear.
      Map<String, dynamic>? toolsResponse;
      final DateTime deadline =
          DateTime.now().add(const Duration(seconds: 20));

      while (DateTime.now().isBefore(deadline)) {
        for (final String line in stdoutLines) {
          if (line.trim().isEmpty) continue;
          try {
            final Map<String, dynamic> decoded =
                jsonDecode(line) as Map<String, dynamic>;
            if (decoded['id'] == 2) {
              toolsResponse = decoded;
              break;
            }
          } catch (_) {
            // Not JSON or not the response we want; keep scanning.
          }
        }
        if (toolsResponse != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      expect(
        toolsResponse,
        isNotNull,
        reason: 'No tools/list (id=2) response received within 20s. '
            'stdout so far: $stdoutLines',
      );

      final List<dynamic> tools =
          (toolsResponse!['result'] as Map<String, dynamic>?)?['tools']
              as List<dynamic>? ??
          <dynamic>[];

      // 5. Assert that the dusk_* slice has exactly 31 entries.
      final List<String> duskToolNames = tools
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> t) => t['name'] as String? ?? '')
          .where((String name) => name.startsWith('dusk_'))
          .toList();

      expect(
        duskToolNames.length,
        equals(31),
        reason:
            'Expected 31 dusk_* tools, got ${duskToolNames.length}. '
            'Full tool names: ${tools.whereType<Map<String, dynamic>>().map((t) => t['name']).toList()}',
      );

      // 6. Verify a sample of canonical alpha-1 tool names are present.
      expect(
        duskToolNames,
        containsAll(<String>['dusk_snap', 'dusk_tap', 'dusk_screenshot']),
        reason:
            'Alpha-1 canonical tool names must be present in the dusk_* slice.',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
