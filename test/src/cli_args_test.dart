import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/cli_args.dart';

void main() {
  group('injectInvocationForMcpInstall()', () {
    test(
      'returns args unchanged when first non-flag arg is not mcp:install',
      () {
        final result = injectInvocationForMcpInstall(['list'], 'tapir');
        expect(result, equals(['list']));
      },
    );

    test(
      'appends --invocation flag when first non-flag arg is mcp:install',
      () {
        final result = injectInvocationForMcpInstall(['mcp:install'], 'tapir');
        expect(result, equals(['mcp:install', '--invocation=tapir']));
      },
    );

    test(
      'preserves user-supplied --invocation=foo equal-form without injecting',
      () {
        final result = injectInvocationForMcpInstall([
          'mcp:install',
          '--invocation=foo',
        ], 'tapir');
        expect(result, equals(['mcp:install', '--invocation=foo']));
      },
    );

    test(
      'preserves user-supplied --invocation whitespace-form without injecting',
      () {
        final result = injectInvocationForMcpInstall([
          'mcp:install',
          '--invocation',
          'foo',
        ], 'tapir');
        expect(result, equals(['mcp:install', '--invocation', 'foo']));
      },
    );
  });
}
