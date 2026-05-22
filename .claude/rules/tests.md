---
paths:
  - "test/**"
---

# Tests

## Layout

Mirror the `lib/src/` tree exactly: `lib/src/extensions/ext_pointer.dart` maps to `test/src/extensions/ext_pointer_test.dart`. One production file, one test file. The provider test lives at `test/dusk_artisan_provider_mcp_tools_test.dart` (direct child of `test/`, mirrors the artisan peer). The CDP smoke lives at `test/integration/cdp_smoke_test.dart` and is tagged `integration` so the default runner excludes it.

Subtree counts (current baseline): `test/src/commands/` 31 files, `test/src/extensions/` 17 files, `test/src/utils/` 3, `test/src/cdp/` 4, `test/src/` 2 (`dusk_plugin_test.dart`, `ref_registry_test.dart`).

## Framework and fakes

`flutter_test` only. No mockito. Stub via contract inheritance: write a private `_FakeNavigateAdapter`, `_FakeEnricher`, `_RecordingArtisanCtx` class inside the test file. Apply the extract-when-third-caller rule before moving a fake to a shared file under `test/_support/`.

No real VM Service connection in any handler test. Handler tests (`test/src/extensions/`) call the handler functions directly (they are `@visibleForTesting` or exported through the file's public surface) and assert on the returned `ServiceExtensionResponse` JSON via `jsonDecode(response.result!) as Map<String, dynamic>`.

CDP tests use `test/src/cdp/fake_cdp_server.dart` (`FakeCdpServer` binds an ephemeral loopback port, serves `/json` + `/json/version` + a WebSocket, routes JSON-RPC to caller-supplied handlers). Never hit a live Chrome process from a unit test; the live path lives in `test/integration/`.

## State isolation

Every test that touches `RefRegistry` adds:

```dart
setUp(RefRegistry.resetForTesting);
tearDown(RefRegistry.resetForTesting);
```

Missing the teardown lets `e<N>` and `q<N>` tokens leak across tests and the next mint produces non-deterministic ref numbers. Tests that replace global handlers (`FlutterError.onError`, hit-test wrappers) must restore them via `addTearDown`:

```dart
final previous = FlutterError.onError;
addTearDown(() => FlutterError.onError = previous);
```

Tests that drive a `WidgetsFlutterBinding` need `TestWidgetsFlutterBinding.ensureInitialized();` at the top of `main()`; `testWidgets` users get this for free.

## Group naming convention

```dart
group('ClassName', () {
  group('.methodName()', () {
    testWidgets('description of the specific behaviour', (tester) async { ... });
  });
});
```

Top-level `group` names the class or extension under test. Nested `group` names the method or `ext.dusk.X` extension (prefix `.` for instance methods). Test description is a plain-English sentence starting with the condition or outcome.

## TDD discipline

Red-green-refactor for every behavioral change. The new test must fail for the right reason before any implementation lands (not a compile error, not a setup error, a genuine assertion failure). Verify this mentally before submitting.

For actionability-gate changes: add a dedicated test per precondition (`enabled`, `zero rect`, `off-viewport`, `not stable`, `obscured`, `defunct`) that asserts on the exact reason substring (`expect(error.reason, contains('off-viewport'))`); agents parse these substrings, so they are load-bearing.

For new MCP tool descriptors: extend `test/dusk_artisan_provider_mcp_tools_test.dart` to assert the tool count (`mcpTools().length`), the new tool's `name`, and its `extensionMethod` route prefix (`ext.dusk.*` versus `artisan:dusk:*`).

## Assertion targets

- **RefRegistry tests**: assert on `RefRegistry.lookup(ref)`, `RefRegistry.lookupQuery(ref)`, `RefRegistry.refsForGroup(groupId).length`. Never reach into private `_entries` / `_queries` maps.
- **Handler tests**: call the handler function directly (`aiTestTapHandler('ext.dusk.tap', params)`), decode the response, assert on the decoded map keys.
- **Provider tests**: instantiate `DuskArtisanProvider()`, assert `commands().length == 32`, `mcpTools().length == 31`, then assert specific descriptor `name` + `extensionMethod` per index range.
- **CDP tests**: spin up `FakeCdpServer`, assert on the recorded JSON-RPC frames (method name + params shape) rather than network bytes.

## Baseline and coverage gate

`flutter test --exclude-tags=integration --timeout=30s` exits 0 with the current passing suite after the 0.0.1 release-prep wave. Pre-existing unrelated failures (logged in `CHANGELOG.md` under `### Risks Accepted`) are flagged in the PR description and not blocking per-step.

Coverage floor 80% enforced by CI (`.github/workflows/ci.yml:42-44`). After every behavioral change verify locally:

```bash
flutter test --coverage --exclude-tags=integration --timeout=30s
awk -F: '/^LF:/{lf+=$2} /^LH:/{lh+=$2} END{ if (lf==0) exit 1; printf "%.2f%%\n", (lh/lf)*100 }' coverage/lcov.info
```

A run that emits below 80% blocks the change. Lift coverage by adding a test that exercises the new branch, never by deleting the new code or excluding it from the lcov tracefile.
