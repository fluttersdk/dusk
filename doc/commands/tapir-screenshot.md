# tapir:screenshot

Capture a screenshot of the running Flutter app to a file. On web targets where dowel was started with `--cdp-port`, the command routes through Chrome DevTools Protocol `Page.captureScreenshot` for a full-viewport capture (bypassing the in-isolate `ext.tapir.screenshot` extension, which hangs under CanvasKit+DWDS, issue #13). On native targets the VM Service handler walks the render tree to find the `RepaintBoundary` that `TapirPlugin.install()` wrapped around the app root, calls `toImage`, and returns a base64-encoded PNG or JPEG. The CLI decodes the payload and writes the bytes to the path supplied by `--output`.

JPEG is the default for size: a typical Flutter web screen renders in ~30 KB at quality 70. Switch to PNG when the agent needs lossless pixels for a diff comparison.

> **Scope:** `tapir:screenshot` captures the full app frame. Region (`ref` / `rect`) capture is not exposed by this command; it is deferred. The CDP fallback applies to the CLI command only; the `tapir_screenshot` MCP tool dispatches `ext.tapir.screenshot` in-isolate and can still time out on web, so prefer the CLI for web screenshots.

---

## Table of contents

- [Synopsis](#synopsis)
- [Arguments](#arguments)
- [Returns](#returns)
- [Format and quality](#format-and-quality)
- [CDP path vs. in-isolate path](#cdp-vs-extension)
- [Examples](#examples)
- [See also](#see-also)

---

<a name="synopsis"></a>
## Synopsis

```
dart run tapir tapir:screenshot --output=<path>
                                          [--format=jpeg|png]
                                          [--quality=<1-100>]
                                          [--ref=<eN|qN>]
                                          [--rect=<x,y,w,h>]
```

`tapir:screenshot` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI. When `cdpPort` is set in state (a web target), the command uses CDP `Page.captureScreenshot`; otherwise it calls `ext.tapir.screenshot`, decodes the base64 payload, and writes the resulting bytes to the supplied output path.

---

<a name="arguments"></a>
## Arguments

| Option | Abbr | Type | Default | Required | Description |
|--------|------|------|---------|----------|-------------|
| `--output` | `-o` | string (path) | (none) | yes (`mandatory: true`) | Output file path. Resolved relative to the CWD. The directory must already exist. |
| `--format` | none | enum | inferred from `--output`, else `jpeg` | no | One of `jpeg`, `png`. Constrained by `allowed: ['jpeg', 'png']` so any other value errors out at parse time. See [Format and quality](#format-and-quality) for the inference. |
| `--quality` | none | int (string-parsed) | `70` | no | JPEG quality, range 1-100. Ignored for PNG. Falls back to `70` when the value fails `int.tryParse`. |
| `--ref` | none | string | (none) | no | Capture only this widget. An `e<N>` token from `tapir:snap` or a `q<N>` handle from `tapir:find`. Omit for the whole viewport. |
| `--rect` | none | string `x,y,w,h` | (none) | no | Sub-rect in logical pixels, relative to the ref's top-left. Requires `--ref`. |

The `--output` guard fires before the VM Service call; an empty or missing path returns exit code `1` with `Missing --output=<path>.`. `--rect` without `--ref` returns `1` as well, rather than quietly capturing the whole frame: a sub-rect is meaningless without the widget it is relative to, and an image that looks right but answers a different question is the failure this flag exists to remove.

---

<a name="returns"></a>
## Returns

`tapir:screenshot` returns an integer exit code via `Future<int>`:

| Exit code | Meaning |
|-----------|---------|
| `0` | Screenshot captured and written. The handler emits `Wrote <N> base64 chars to <path>` where `<N>` is the length of the base64 string before decoding (useful for spotting empty buffers without inspecting the file). |
| `1` | `--output` was missing or empty (CLI-side guard); OR the VM Service handler returned a response without a `base64` field. |

**Success envelope (CLI side):**

```
[ok]      Wrote 41268 base64 chars to /tmp/dashboard.jpeg
```

**VM Service envelope (handler side):**

```json
{ "base64": "<base64-encoded image bytes>" }
```

The CLI calls `base64Decode(base64Str)` and writes the resulting bytes to `output`. No additional metadata (width, height, mime) is returned today; the agent infers shape from the file on disk if needed.

---

<a name="format-and-quality"></a>
## Format and quality

When `--format` is not given, the format follows the `--output` extension: `.png` captures PNG, `.jpg` and `.jpeg` capture JPEG, so a `.png` file never holds JPEG bytes. Any other extension falls back to `jpeg`. An explicit `--format` always wins; when it disagrees with the extension (`--output=a.png --format=jpeg`) the command writes the file as asked and warns on stderr that the file will hold the other format's bytes.

- **jpeg** (default): on native targets the VM Service handler encodes via the `image` package's JPEG encoder at the supplied quality; on web (CDP path) the `format` + `quality` params are forwarded directly to `Page.captureScreenshot`. Quality 70 is a Playwright-aligned default; bump to 90 for visual-regression diffs, drop to 40 for quick sanity checks.
- **png**: lossless, larger files (typically 5x JPEG at quality 70). The `--quality` value is ignored.

On a hidden or minimised desktop window the in-isolate path used to return the last cached frame. Tapir now wakes the app before capturing (the response carries `framesForced: true`), so the image is fresh. The CDP path on web is unaffected by the lifecycle. See [Frame production](../reference/frame-production.md).

The handler never resizes the screenshot; the captured image matches the running viewport's pixel dimensions (logical size times DPR). To capture at a controlled viewport, run `tapir:resize` or `tapir:device` first.

---

<a name="cdp-vs-extension"></a>
## CDP path vs. in-isolate path

| Condition | Path taken |
|---|---|
| No `cdpPort` in state (native target) | `ext.tapir.screenshot` (in-isolate) |
| `cdpPort` set (web target) | CDP `Page.captureScreenshot` |

The CDP path sends `Page.enable` first (required by Chrome before `Page.captureScreenshot`), then `Page.captureScreenshot` with `fromSurface: true`. The resulting dimensions reflect the `Emulation.setDeviceMetricsOverride` still in force, which is only one whose DevTools session is still open (`tapir:resize --hold`); Chrome drops it when the session that sent it detaches.

**`--ref` works on both paths, by different routes.** In-isolate, `ext.tapir.screenshot` rasterises the ref's own render-object region directly. Over CDP there is no notion of a Flutter ref, so the command first asks the extension for the region in geometry mode, which resolves `--ref` / `--rect` and returns the rect without rasterising (the rasterise is exactly what hangs on this target), then passes it to `Page.captureScreenshot` as a `clip`. Flutter logical pixels and CDP CSS pixels are the same unit, so the rect crosses over unscaled.

One extra round-trip, and one definition of what a ref covers rather than two. When the ref no longer resolves the command exits `1` instead of falling back to a full-frame capture.

---

<a name="examples"></a>
## Examples

### 1. Capture the current screen as JPEG

```bash
dart run tapir tapir:screenshot --output=/tmp/screen.jpeg
```

Expected output (illustrative):

```
[ok]      Wrote 41268 base64 chars to /tmp/screen.jpeg
```

### 2. Capture losslessly for a visual diff

```bash
dart run tapir tapir:screenshot --output=/tmp/screen.png --format=png
```

Useful when the agent compares against a baseline PNG via `image_diff` or `pixelmatch`.

### 3. Capture at high quality JPEG

```bash
dart run tapir tapir:screenshot --output=/tmp/hifi.jpeg --quality=92
```

### 4. Capture after a controlled resize

```bash
# The override lives only as long as the session that sent it: hold it.
dart run tapir tapir:resize --width=1440 --height=900 --hold &
dart run tapir tapir:screenshot --output=/tmp/desktop.jpeg
```

### 5. Capture one component instead of the whole screen

```bash
dart run tapir tapir:snap | grep 'PricingCard'
# - region "PricingCard" [ref=e42] ...
dart run tapir tapir:screenshot --output=/tmp/card.png --format=png --ref=e42
```

Reach for this whenever the question is about one component. A full-screen capture of a tall page costs far more tokens than the region under review, and it buries the thing you are actually checking. It also removes the resize dance: without `--ref`, seeing a component below the fold means growing the viewport to something no device has, capturing, and putting the height back.

### 6. Capture part of a component

```bash
# The top-left 200x60 of the card, in logical pixels relative to its own origin.
dart run tapir tapir:screenshot --output=/tmp/card-header.png --ref=e42 --rect=0,0,200,60
```

---

<a name="see-also"></a>
## See also

- [tapir:snap](tapir-snap.md): the structured-text counterpart; agents typically pair `tapir:snap` and `tapir:screenshot` to read both the Semantics tree and the pixels in a single round.
- [tapir:hot_reload_and_snap](index.md#hot-reload-and-snap): captures snapshot + screenshot + recent exceptions in one round trip.
- [tapir:resize](index.md#cdp) and [tapir:device](index.md#cdp): control the viewport that `tapir:screenshot` captures from on web targets.
