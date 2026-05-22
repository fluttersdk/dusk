# Quickstart

A 3-step walkthrough from zero to driving the bundled `example/` Flutter app with a
snap, a tap, and a screenshot via the dusk CLI.

Prerequisites: Flutter `>= 3.22.0` SDK installed, `fluttersdk_dusk` added to your
project (see [Installation](installation)), and `DuskPlugin.install()` wired inside
`kDebugMode` in your `main.dart`.

---

### 1. Start the example app and capture a snapshot

Clone the repository (or navigate to the package root if you are working from source),
then launch the bundled example app in Chrome:

```bash
cd example
flutter run -d chrome
```

Leave the browser window open and open a second terminal in the same directory. Run
`dusk:snap` to walk the live Semantics tree and emit a YAML snapshot:

```bash
dart run fluttersdk_artisan dusk:snap
```

The command connects to the running app via the VM Service, walks every visible
Semantics node, and prints a snapshot to stdout. A minimal output looks like this:

```yaml
snapshot:
  - ref: e1
    role: button
    label: "Increment"
    bounds: {left: 312, top: 548, width: 56, height: 56}
  - ref: e2
    role: text
    label: "You have pushed the button 0 times."
    bounds: {left: 100, top: 300, width: 600, height: 24}
  - ref: e3
    role: text
    label: "0"
    bounds: {left: 100, top: 340, width: 600, height: 48}
```

Each node has a `ref:` token (here `e1`, `e2`, `e3`). These tokens are stable for the
lifetime of the snapshot and are what you pass to action commands in the next step.

---

### 2. Tap a widget using its ref token

Locate the ref token for the target widget in the snapshot output above. The counter
increment button is `e1`. Pass that token to `dusk:tap`:

```bash
dart run fluttersdk_artisan dusk:tap --ref=e1
```

The extension looks up `e1` in the frozen snapshot registry, checks the actionability
gate (the widget must be enabled, have a non-zero bounding rect, and be on-viewport),
then synthesizes a pointer-down + pointer-up event pair at the widget's center. The
app responds as if a real user tapped the button.

A successful tap returns a JSON confirmation:

```json
{"action": "tap", "ref": "e1", "label": "Increment", "ok": true}
```

If the widget fails the actionability gate, the command exits with an error message:

```
Widget ref=e1 is not actionable: not enabled
```

Re-snap (`dusk:snap`) after a tap to confirm the UI updated. In this example the
counter label `e3` should now show `"1"` in the refreshed snapshot.

---

### 3. Capture a screenshot

Capture a PNG of the current viewport to verify the app state visually or to save a
baseline image:

```bash
dart run fluttersdk_artisan dusk:screenshot --output=counter_after_tap.png
```

The extension walks the render tree to find the `RepaintBoundary` that
`DuskPlugin.install()` wraps around the app root, captures a raster frame, and writes
the PNG to the path you specify. The file lands relative to your current working
directory.

Expected output:

```
Screenshot saved to counter_after_tap.png (1280x800)
```

Open the file to confirm the counter reads 1 after the tap in step 2. You now have
the full snap-tap-screenshot loop working end-to-end.

---

## What's next?

- Read the [commands catalog](../commands/) to see all 32 dusk CLI commands and their
  flags.
- Set up the [MCP server](../mcp/setup) so Claude Code or Cursor can call dusk tools
  directly during a conversation.
- Add [MagicDuskIntegration](../plugins/magic-integration.md) (Magic stack) or call
  `Wind.installDebugResolver()` (Wind alpha-10+; see [Wind integration](../plugins/wind-integration.md))
  to enrich snapshots with framework-specific metadata.
- Explore the [actionability gate reference](../reference/actionability-gate) to
  understand how dusk decides whether a widget is safe to interact with.

---

All three commands shown above are part of the `fluttersdk_dusk` built-in surface.
No additional packages are needed beyond `fluttersdk_artisan` (MCP server and CLI
host) and `fluttersdk_dusk` (VM Service extensions) installed in step 1.
