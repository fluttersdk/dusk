---
paths: test/**
---

# Tests: Rules

## Layout

- Test tree mirrors `lib/src/` one-to-one. Example: `lib/src/extensions/ext_tap.dart` maps to `test/src/extensions/ext_tap_test.dart`. One production file, one test file.
- Publishing-harness tests live under `test/publishing/` and use plain `test` (no widget mount).

## Fakes and stubs

- No mockito. Stub via contract inheritance or plain fakes declared inside the test file.
- Fake class names are file-private (`_FakeX`). Never export fakes.

## RefRegistry teardown

- Call `RefRegistry.resetForTesting()` in every `tearDown` block. Forgetting this leaks ref state across tests and produces ordering-dependent failures that are hard to diagnose.

## Widget tests

- Size the surface when layout depends on viewport:
  ```dart
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  ```
- Call `await tester.pumpAndSettle()` after every async operation that triggers a rebuild; `find.byType` sees the pre-rebuild tree otherwise.

## Fixture classes

- Use `final class` for every new test fixture or fake. No abstract fakes unless a genuine hierarchy is required.

## TDD

- Red-green-refactor is mandatory for every behavioral change. Write the failing assertion first; confirm it fails for the right reason (not a setup error); then implement; then re-run to confirm green.
- Reverting the implementation must turn the test red again. A test that stays green without the implementation is not testing anything.
- Coverage gate: `flutter test --coverage` must report line coverage at or above 80% across `lib/`. Drops below 80% block the change.
