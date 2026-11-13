# Quickstart

A three-step walkthrough from zero to driving the bundled `example/` Flutter app with a snapshot, a tap and a screenshot through the tapir CLI.

Prerequisites: a Flutter `>= 3.22.0` SDK and a clone of the repository. The `example/` app already calls `TapirPlugin.install()` inside `!kReleaseMode` and resolves `tapir` from the parent directory. To drive your own app instead, follow [Installation](installation.md) first.

- [1. Start the example app and capture a snapshot](#1-start-the-example-app)
- [2. Tap a widget using its ref token](#2-tap-a-widget)
- [3. Capture a screenshot](#3-capture-a-screenshot)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

---

<a name="1-start-the-example-app"></a>
## 1. Start the example app and capture a snapshot

Start the app through dowel, so the session (the VM Service URI every `tapir:*` command dials) is recorded. The `--cdp-port` makes web screenshots reliable in step 3; on a native target (`--device=macos`, for example) leave it out:

```bash
cd example
flutter pub get
dart run tapir start --device=chrome --cdp-port=9333
```

Once the app is up, run `tapir:snap` in the same directory to walk the live Semantics tree. The example has many widgets, so narrow the walk with `--grep` to the counter button:

```bash
dart run tapir tapir:snap --grep=Counter
```

The command connects to the running app via the VM Service and prints the snapshot to stdout. An illustrative output (ancestor lines trimmed):

```yaml
- button "Counter: 0" [ref=e1]
```

Each interactive node carries a `[ref=eN]` token (here `e1`). Tokens are frozen to that snapshot: every fresh `tapir:snap` mints new ones, and they are what you pass to action commands in the next step.

---

<a name="2-tap-a-widget"></a>
## 2. Tap a widget using its ref token

Pass the ref token from the snapshot to `tapir:tap`:

```bash
dart run tapir tapir:tap --ref=e1
```

The extension looks up `e1` in the snapshot registry, runs the actionability gate (see [Reference: Actionability gate](../reference/actionability-gate.md): the widget must be enabled, have a non-zero rect, be on-viewport, stable, and receive pointer events), then synthesises a pointer-down and pointer-up pair at the widget's centre. The app responds as if a real user tapped the button.

A successful tap prints one line:

```
✓ Tapped e1
```

When nothing observable changed, the line reads `Tapped e1 (no observable change)`; read it before concluding the tap worked. Add `--json` for the full envelope, which carries the `effect` block.

If the widget fails the actionability gate, the command exits with an error message:

```
Widget ref=e1 is not actionable: not enabled
```

Re-snap after a tap to confirm the UI updated. The refreshed snapshot shows the button as `Counter: 1`, under a new ref:

```bash
dart run tapir tapir:snap --grep=Counter
```

---

<a name="3-capture-a-screenshot"></a>
## 3. Capture a screenshot

Capture an image of the current viewport to verify the app state visually or to save a baseline:

```bash
dart run tapir tapir:screenshot --output=counter_after_tap.png
```

On web with `--cdp-port` the command captures through Chrome DevTools Protocol; on a native target it asks the app's `RepaintBoundary` for a frame. The file lands relative to your current working directory, and the format follows the `--output` extension.

Expected output:

```
✓ Wrote 48213 bytes (47.1 KB, png) to counter_after_tap.png
```

Open the file to confirm the button reads `Counter: 1`. You now have the full snap, tap and screenshot loop working end to end. Stop the app with `dart run tapir stop`.

---

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Running `flutter run` by hand, then `tapir:snap` finds no app. | Start the app with `dart run tapir start`, which records the session the `tapir:*` commands dial. |
| Tapping an `eN` ref from an earlier snapshot after the screen changed. | Re-snap and use the fresh ref, or mint a `qN` handle with `tapir:find` that survives rebuilds. |
| The web screenshot hangs or returns an error. | Start with `--cdp-port=<port>` so the CLI captures through Chrome DevTools Protocol. |
| The tap printed `no observable change`. | The gate accepted the tap but the widget did not react: re-snap and check the result before relying on it. |

<a name="related-documentation"></a>
## Related Documentation

- [Commands](../commands/index.md): every `tapir:*` command with its flags.
- [MCP setup](../mcp/setup.md): let Claude Code or Cursor call the tapir tools directly during a conversation.
- [Magic integration](../plugins/magic-integration.md) and [Wind integration](../plugins/wind-integration.md): enrich snapshots with framework-specific metadata (`MagicTapirIntegration.install()`, `Wind.installDebugResolver()`).
- [Reference: Actionability gate](../reference/actionability-gate.md): how tapir decides whether a widget is safe to interact with.
