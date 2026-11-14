import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/tapir.dart';

/// The public surface of `package:tapir/tapir.dart`, through the barrel
/// alone: what `magic_devtools`, the docs and an app use. A name this test
/// reaches is API; a name it cannot reach (the semantics handle, the boot id
/// minting, the install counter, the ref registry's test helpers) stays
/// inside `src/`, which the analyzer enforces at compile time here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the host hooks resolve through the barrel', () {
    expect(TapirPlugin.enrichers, isA<List<TapirSnapshotEnricher>>());
    expect(TapirPlugin.isDisabled, isFalse);
    expect(TapirPlugin.navigateAdapter, isNull);
    TapirPlugin.registerNavigateAdapter(null);
    expect(RefRegistry.instance, isA<RefRegistry>());
    expect(TapirDowelProvider().commands(), isNotEmpty);
  });

  test('the log and exception readers take one request object', () {
    final List<Map<String, Object?>> Function(ConsoleRequest) logs =
        recentLogsReader;
    final List<Map<String, Object?>> Function(ExceptionsRequest) exceptions =
        recentExceptionsReader;
    addTearDown(() {
      recentLogsReader = logs;
      recentExceptionsReader = exceptions;
    });

    ConsoleRequest? seenLogs;
    ExceptionsRequest? seenExceptions;
    recentLogsReader = (ConsoleRequest request) {
      seenLogs = request;
      return const <Map<String, Object?>>[];
    };
    recentExceptionsReader = (ExceptionsRequest request) {
      seenExceptions = request;
      return const <Map<String, Object?>>[];
    };

    recentLogsReader(const ConsoleRequest(limit: 5, minLevel: 'WARNING'));
    recentExceptionsReader(const ExceptionsRequest(limit: 7));

    expect(seenLogs!.limit, 5);
    expect(seenLogs!.minLevel, 'WARNING');
    expect(seenExceptions!.limit, 7);
    expect(const ConsoleRequest().limit, 50);
    expect(const ExceptionsRequest().limit, 20);
  });
}
