import 'package:flutter_test/flutter_test.dart';

import 'package:tapir/src/utils/snapshot_diff.dart';

String _snap(List<String> lines) => '${lines.join('\n')}\n';

void main() {
  group('diffSnapshots', () {
    test('a first call with no baseline returns the full text', () {
      final String current = _snap(<String>[
        '- button "Save" [ref=e1]',
        '- text "Saved"',
      ]);

      expect(diffSnapshots(null, current), equals(current));
    });

    test('a changed value reports the old line then the new one', () {
      final String previous = _snap(<String>[
        '- heading "Home" [ref=e1]',
        '- button "Counter: 0" [ref=e5]',
      ]);
      final String current = _snap(<String>[
        '- heading "Home" [ref=e1]',
        '- button "Counter: 1" [ref=e5]',
      ]);

      expect(
        diffSnapshots(previous, current),
        equals(
          '- - button "Counter: 0" [ref=e5]\n'
          '+ - button "Counter: 1" [ref=e5]\n'
          '(2 of 2 lines changed)',
        ),
      );
    });

    test('an added row is prefixed with a plus', () {
      final String previous = _snap(<String>['- button "Save" [ref=e1]']);
      final String current = _snap(<String>[
        '- button "Save" [ref=e1]',
        '- button "Cancel" [ref=e2]',
      ]);

      expect(
        diffSnapshots(previous, current),
        equals(
          '+ - button "Cancel" [ref=e2]\n'
          '(1 of 2 lines changed)',
        ),
      );
    });

    test('a removed row is prefixed with a minus', () {
      final String previous = _snap(<String>[
        '- button "Save" [ref=e1]',
        '- button "Cancel" [ref=e2]',
      ]);
      final String current = _snap(<String>['- button "Save" [ref=e1]']);

      expect(
        diffSnapshots(previous, current),
        equals(
          '- - button "Cancel" [ref=e2]\n'
          '(1 of 1 lines changed)',
        ),
      );
    });

    test('a marker-only change is not a change', () {
      final String previous = _snap(<String>[
        '- button "Save" [ref=e1]',
        '- button "Away" [ref=e2] [offscreen]',
      ]);
      final String current = _snap(<String>[
        '- button "Save" [ref=e1] [occluded]',
        '- button "Away" [ref=e2]',
      ]);

      expect(
        diffSnapshots(previous, current),
        equals('(0 of 2 lines changed)'),
      );
    });

    test(
      'a changed value alongside a marker change reports the whole line',
      () {
        final String previous = _snap(<String>[
          '- button "Counter: 0" [ref=e5] [offscreen]',
        ]);
        final String current = _snap(<String>[
          '- button "Counter: 1" [ref=e5]',
        ]);

        expect(
          diffSnapshots(previous, current),
          equals(
            '- - button "Counter: 0" [ref=e5] [offscreen]\n'
            '+ - button "Counter: 1" [ref=e5]\n'
            '(2 of 1 lines changed)',
          ),
        );
      },
    );

    test('lines without a ref are compared by their text', () {
      final String previous = _snap(<String>[
        '- text "Loading"',
        '- text "Footer"',
      ]);
      final String current = _snap(<String>[
        '- text "Done"',
        '- text "Footer"',
      ]);

      expect(
        diffSnapshots(previous, current),
        equals(
          '+ - text "Done"\n'
          '- - text "Loading"\n'
          '(2 of 2 lines changed)',
        ),
      );
    });

    test('repeated identical lines are matched one for one', () {
      final String previous = _snap(<String>['- text "Row"', '- text "Row"']);
      final String current = _snap(<String>[
        '- text "Row"',
        '- text "Row"',
        '- text "Row"',
      ]);

      expect(
        diffSnapshots(previous, current),
        equals(
          '+ - text "Row"\n'
          '(1 of 3 lines changed)',
        ),
      );
    });

    test('an identical snapshot reports nothing changed', () {
      final String same = _snap(<String>['- button "Save" [ref=e1]']);

      expect(diffSnapshots(same, same), equals('(0 of 1 lines changed)'));
    });
  });
}
