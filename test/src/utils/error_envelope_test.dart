import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/utils/error_envelope.dart';

void main() {
  group('DuskErrorEnvelope.toJson', () {
    test('(a) emits type + widgetPath + suggestions verbatim', () {
      const DuskErrorEnvelope envelope = DuskErrorEnvelope(
        type: 'not_found',
        widgetPath: 'e7',
        suggestions: <String>['Submit', 'Submitted', 'Submission'],
      );

      expect(
        envelope.toJson(),
        equals(<String, dynamic>{
          'type': 'not_found',
          'widget_path': 'e7',
          'suggestions': <String>['Submit', 'Submitted', 'Submission'],
        }),
      );
    });

    test('(b) omits widgetPath when null but always emits empty suggestions',
        () {
      const DuskErrorEnvelope envelope = DuskErrorEnvelope(
        type: 'unexpected',
        widgetPath: null,
        suggestions: <String>[],
      );

      final Map<String, dynamic> json = envelope.toJson();

      expect(json['type'], equals('unexpected'));
      expect(json.containsKey('widget_path'), isFalse);
      expect(json['suggestions'], equals(<String>[]));
    });
  });

  group('levenshtein helper', () {
    test('(a) identical strings have distance 0', () {
      expect(levenshtein('Submit', 'Submit'), equals(0));
    });

    test('(b) single-character substitution costs 1', () {
      expect(levenshtein('Submit', 'Submiu'), equals(1));
    });

    test('(c) extra trailing characters count as inserts', () {
      expect(levenshtein('Submi', 'Submit'), equals(1));
      expect(levenshtein('Sub', 'Submit'), equals(3));
    });

    test('(d) empty strings handled', () {
      expect(levenshtein('', ''), equals(0));
      expect(levenshtein('', 'abc'), equals(3));
      expect(levenshtein('abc', ''), equals(3));
    });
  });

  group('fuzzyMatch helper', () {
    test('(a) top-3 by distance, threshold 3, filters out anything farther',
        () {
      final List<String> suggestions = fuzzyMatch(
        'Submi',
        <String>[
          'Submit',
          'Submitted',
          'Submission',
          'Cancel',
          'Logout',
          'Profile',
        ],
      );

      expect(suggestions, hasLength(3));
      expect(suggestions, contains('Submit'));
      expect(suggestions, contains('Submitted'));
      expect(suggestions, contains('Submission'));
      // Far-away candidates filtered out.
      expect(suggestions, isNot(contains('Cancel')));
    });

    test('(b) returns fewer than 3 when fewer candidates clear the threshold',
        () {
      final List<String> suggestions = fuzzyMatch(
        'Submit',
        <String>['Submit', 'WildlyDifferent', 'AnotherUnrelated'],
      );

      expect(suggestions, equals(<String>['Submit']));
    });

    test('(c) deduplicates and preserves ascending distance order', () {
      final List<String> suggestions = fuzzyMatch(
        'Save',
        <String>['Save', 'Save', 'Sav', 'Saves'],
      );

      expect(suggestions.first, equals('Save'));
      expect(suggestions.length, lessThanOrEqualTo(3));
      expect(suggestions.toSet().length, equals(suggestions.length));
    });

    test('(d) returns empty list when query is empty', () {
      expect(
        fuzzyMatch('', <String>['Save', 'Cancel']),
        isEmpty,
      );
    });
  });

  group('DuskErrorEnvelope.notFound factory', () {
    test('(a) carries type=not_found and widgetPath + fuzzy suggestions', () {
      final DuskErrorEnvelope envelope = DuskErrorEnvelope.notFound(
        ref: 'Submi',
        candidates: <String>['Submit', 'Submitted', 'Submission', 'Cancel'],
      );

      expect(envelope.type, equals('not_found'));
      expect(envelope.widgetPath, equals('Submi'));
      expect(envelope.suggestions, hasLength(3));
      expect(envelope.suggestions, contains('Submit'));
      expect(envelope.suggestions, contains('Submitted'));
      expect(envelope.suggestions, contains('Submission'));
    });

    test('(b) empty candidates yields empty suggestions list', () {
      final DuskErrorEnvelope envelope = DuskErrorEnvelope.notFound(
        ref: 'e9999',
        candidates: const <String>[],
      );

      expect(envelope.type, equals('not_found'));
      expect(envelope.suggestions, isEmpty);
    });
  });

  group('DuskErrorEnvelope.fromActionabilityReason factory', () {
    test('(a) "not enabled" → disabled', () {
      final DuskErrorEnvelope envelope =
          DuskErrorEnvelope.fromActionabilityReason('e3', 'not enabled');
      expect(envelope.type, equals('disabled'));
      expect(envelope.widgetPath, equals('e3'));
    });

    test('(b) "zero rect" → zero_rect', () {
      final DuskErrorEnvelope envelope =
          DuskErrorEnvelope.fromActionabilityReason('e1', 'zero rect');
      expect(envelope.type, equals('zero_rect'));
    });

    test('(c) "off-viewport (rect=..., viewport=...)" → off_viewport', () {
      final DuskErrorEnvelope envelope =
          DuskErrorEnvelope.fromActionabilityReason(
        'e2',
        'off-viewport (rect=Rect.fromLTRB(5000.0, 5000.0, 5050.0, 5050.0), '
            'viewport=Rect.fromLTRB(0.0, 0.0, 800.0, 600.0))',
      );
      expect(envelope.type, equals('off_viewport'));
    });

    test('(d) "not stable (rect changed by 2.0px)" → not_stable', () {
      final DuskErrorEnvelope envelope =
          DuskErrorEnvelope.fromActionabilityReason(
        'e4',
        'not stable (rect changed by 2.0px)',
      );
      expect(envelope.type, equals('not_stable'));
    });

    test('(e) "obscured by other widget (top=...)" → obscured', () {
      final DuskErrorEnvelope envelope =
          DuskErrorEnvelope.fromActionabilityReason(
        'e5',
        'obscured by other widget (top=ModalBarrier)',
      );
      expect(envelope.type, equals('obscured'));
    });

    test('(f) unknown reason → unexpected', () {
      final DuskErrorEnvelope envelope =
          DuskErrorEnvelope.fromActionabilityReason('e6', 'whatever new gate');
      expect(envelope.type, equals('unexpected'));
    });
  });

  group('Other envelope factories', () {
    test('stale ref → stale type with widgetPath', () {
      final DuskErrorEnvelope envelope = DuskErrorEnvelope.stale('q3');
      expect(envelope.type, equals('stale'));
      expect(envelope.widgetPath, equals('q3'));
    });

    test('missing param → missing_param', () {
      final DuskErrorEnvelope envelope = DuskErrorEnvelope.missingParam('ref');
      expect(envelope.type, equals('missing_param'));
      expect(envelope.widgetPath, isNull);
    });

    test('timeout factory', () {
      final DuskErrorEnvelope envelope = DuskErrorEnvelope.timeout();
      expect(envelope.type, equals('timeout'));
    });

    test('unexpected factory', () {
      final DuskErrorEnvelope envelope = DuskErrorEnvelope.unexpected();
      expect(envelope.type, equals('unexpected'));
    });
  });

  group('wrapErrorDetail', () {
    test('(a) produces JSON carrying both message and envelope', () {
      const DuskErrorEnvelope envelope = DuskErrorEnvelope(
        type: 'not_found',
        widgetPath: 'e9999',
        suggestions: <String>[],
      );

      final String wire = wrapErrorDetail(
        'ext.dusk.tap: ref "e9999" not found in registry',
        envelope,
      );

      // Legacy substring contract — agents grep these substrings. JSON
      // escapes interior quotes, so unquoted phrases pass through verbatim.
      expect(wire, contains('not found in registry'));
      expect(wire, contains('ext.dusk.tap'));

      // Structured access — parseEnvelopeFromErrorDetail decodes envelope.
      final Map<String, dynamic>? decoded = parseEnvelopeFromErrorDetail(wire);
      expect(decoded, isNotNull);
      expect(decoded!['type'], equals('not_found'));
      expect(decoded['widget_path'], equals('e9999'));

      // Original message is recoverable verbatim (with literal quotes).
      expect(
        parseMessageFromErrorDetail(wire),
        equals('ext.dusk.tap: ref "e9999" not found in registry'),
      );
    });

    test('(b) preserves every actionability reason substring', () {
      for (final String reason in <String>[
        'not enabled',
        'zero rect',
        'off-viewport',
        'not stable',
        'obscured by',
      ]) {
        final String message = 'Widget ref=e1 is not actionable: $reason';
        final DuskErrorEnvelope envelope =
            DuskErrorEnvelope.fromActionabilityReason('e1', reason);
        final String wire = wrapErrorDetail(message, envelope);
        expect(wire, contains(reason));
        expect(wire, contains('Widget ref=e1 is not actionable'));
      }
    });

    test('(c) parseEnvelopeFromErrorDetail returns null for legacy strings',
        () {
      expect(
        parseEnvelopeFromErrorDetail('Plain pre-3.3 error message'),
        isNull,
      );
    });

    test('(d) parseMessageFromErrorDetail returns input for legacy strings',
        () {
      expect(
        parseMessageFromErrorDetail('Plain pre-3.3 error message'),
        equals('Plain pre-3.3 error message'),
      );
    });
  });
}
