import 'dart:convert';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/perf/perf_redaction.dart';

/// A secret with both characters that change under `jsonEncode` or a shell.
const String _kSecret = r'hun"ter$2';

void main() {
  group('PerfRedactor', () {
    group('.redact()', () {
      test('masks the raw value and its jsonEncode inner form', () {
        final PerfRedactor redactor = PerfRedactor(<String>{_kSecret});
        final String inner = jsonEncode(_kSecret).substring(
          1,
          jsonEncode(_kSecret).length - 1,
        );

        final String masked = redactor.redact(
          'typed $_kSecret, answered {"text":"$inner"}',
        );

        expect(masked, 'typed ***, answered {"text":"***"}');
      });

      test('masks the longer secret first, so a shorter one leaves no tail',
          () {
        final PerfRedactor redactor = PerfRedactor(<String>{
          'abc',
          'abcdef',
        });

        expect(redactor.redact('x abcdef y abc'), 'x *** y ***');
      });

      test('is the identity with no secrets', () {
        expect(PerfRedactor(const <String>{}).redact('a "b" \$c'), 'a "b" \$c');
      });
    });

    group('.redactJson()', () {
      test('masks every string leaf and leaves numbers and keys alone', () {
        final PerfRedactor redactor = PerfRedactor(<String>{_kSecret});

        final Object? masked = redactor.redactJson(<String, Object?>{
          'reason': 'fill refused $_kSecret',
          'count': 2,
          'nested': <Object?>[
            'ok',
            <String, Object?>{'text': _kSecret},
            true,
            null,
          ],
        });

        expect(masked, <String, Object?>{
          'reason': 'fill refused ***',
          'count': 2,
          'nested': <Object?>[
            'ok',
            <String, Object?>{'text': '***'},
            true,
            null,
          ],
        });
      });
    });
  });

  group('RedactingOutput', () {
    test('masks every line before the wrapped output sees it', () {
      final BufferedOutput inner = BufferedOutput(verbosity: 4);
      final RedactingOutput output = RedactingOutput(
        inner,
        PerfRedactor(<String>{_kSecret}),
      );

      output
        ..writeln('writeln $_kSecret')
        ..info('info $_kSecret')
        ..success('success $_kSecret')
        ..warning('warning $_kSecret')
        ..error('error $_kSecret')
        ..comment('comment $_kSecret')
        ..debug('debug $_kSecret');

      expect(inner.content, isNot(contains(_kSecret)));
      expect(
        inner.content.trim().split('\n'),
        <String>[
          'writeln ***',
          'info ***',
          'success ***',
          'warning ***',
          '[ERROR] error ***',
          'comment ***',
          '[debug] debug ***',
        ],
      );
    });

    test('keeps the wrapped verbosity and level', () {
      final BufferedOutput inner = BufferedOutput();
      final RedactingOutput output = RedactingOutput(
        inner,
        PerfRedactor(const <String>{}),
      );

      output
        ..writeln('shown')
        ..comment('hidden at verbosity 1');

      expect(output.verbosity, 1);
      expect(inner.content.trim(), 'shown');
    });
  });
}
