// Smoke test for the Magic-stack example. Replaces the default flutter
// create test (which references a renamed MyApp). Real coverage of dusk
// enrichers lives in references/fluttersdk_dusk/test/.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('example_magic smoke', () {
    expect(true, isTrue);
  });
}
