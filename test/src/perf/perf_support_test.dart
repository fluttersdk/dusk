import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_dusk/src/perf/perf_support.dart';

void main() {
  group('perfMap() and perfList()', () {
    test('answer the value of their own JSON type, else an empty one', () {
      expect(perfMap(<String, dynamic>{'a': 1}), <String, dynamic>{'a': 1});
      expect(perfMap(<dynamic>[1]), isEmpty);
      expect(perfMap(null), isEmpty);
      expect(perfList(<dynamic>[1, 2]), <dynamic>[1, 2]);
      expect(perfList(<String, dynamic>{}), isEmpty);
      expect(perfList('x'), isEmpty);
    });
  });

  group('perfReadBool()', () {
    test('reads a bool, "true" and "1" as true, anything else as false', () {
      expect(perfReadBool(true), isTrue);
      expect(perfReadBool('true'), isTrue);
      expect(perfReadBool('1'), isTrue);
      expect(perfReadBool(false), isFalse);
      expect(perfReadBool('yes'), isFalse);
      expect(perfReadBool(null), isFalse);
      expect(perfReadBool(1), isFalse);
    });
  });

  group('perfJsonInner()', () {
    test('is the JSON string form without its quotes', () {
      expect(perfJsonInner(r'ab"c$d'), r'ab\"c$d');
      expect(perfJsonInner('plain'), 'plain');
    });
  });

  group('perfAbsolutePath() and perfShownPath()', () {
    test('resolve against the working directory and show relative to a file',
        () {
      final String sep = Platform.pathSeparator;
      final String absolute = perfAbsolutePath('a$sep..${sep}b.yaml');

      expect(absolute, '${Directory.current.absolute.path}${sep}b.yaml');
      expect(
        perfShownPath('${sep}perf${sep}f${sep}login.yaml',
            file: '${sep}perf${sep}campaign.yaml'),
        'f${sep}login.yaml',
      );
      expect(
        perfShownPath('${sep}elsewhere${sep}x.yaml',
            file: '${sep}perf${sep}campaign.yaml'),
        '${sep}elsewhere${sep}x.yaml',
      );
    });
  });
}
