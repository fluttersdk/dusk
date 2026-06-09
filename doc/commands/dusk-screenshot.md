# dusk:screenshot

Capture a screenshot of the running Flutter app to a file. On web targets where artisan was started with `--cdp-port`, the command routes through Chrome DevTools Protocol `Page.captureScreenshot` for a full-viewport capture (bypassing the in-isolate `ext.dusk.screenshot` extension, which hangs under CanvasKit+DWDS, issue #13). On native targets the VM Service handler walks the render tree to find the `RepaintBoundary` that `DuskPlugin.install()` wrapped around the app root, calls `toImage`, and returns a base64-encoded PNG or JPEG. The CLI decodes the payload and writes the bytes to the path supplied by `--output`.

JPEG is the default for size: a typical Flutter web screen renders in ~30 KB at quality 70. Switch to PNG when the agent needs lossless pixels for a diff comparison.

> **Scope:** `dusk:screenshot` captures the full app frame. Region (`ref` / `rect`) capture is not exposed by this command; it is deferred. The CDP fallback applies to the CLI command only; the `dusk_screenshot` MCP tool dispatches `ext.dusk.screenshot` in-isolate and can still time out on web, so prefer the CLI for web screenshots.

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
dart run fluttersdk_dusk dusk:screenshot --output=<path>
                                          [--format=jpeg|png]
                                          [--quality=<1-100>]
```

`dusk:screenshot` requires a running Flutter session (`CommandBoot.connected`). It dials the VM Service URI. When `cdpPort` is set in state (a web target), the command uses CDP `Page.captureScreenshot`; otherwise it calls `ext.dusk.screenshot`, decodes the base64 payload, and writes the resulting bytes to the supplied output path.

---

<a name="arguments"></a>
## Arguments

| Option | Abbr | Type | Default | Required | Description |
|--------|------|------|---------|----------|-------------|
| `--output` | `-o` | string (path) | (none) | yes (`mandatory: true`) | Output file path. Resolved relative to the CWD. The directory must already exist. |
| `--format` | none | enum | `jpeg` | no | One of `jpeg`, `png`. Constrained by `allowed: ['jpeg', 'png']` so any other value errors out at parse time. |
| `--quality` | none | int (string-parsed) | `70` | no | JPEG quality, range 1-100. Ignored for PNG. Falls back to `70` when the value fails `int.tryParse`. |

The `--output` guard fires before the VM Service call; an empty or missing path returns exit code `1` with `Missing --output=<path>.`.

---

<a name="returns"></a>
## Returns

`dusk:screenshot` returns an integer exit code via `Future<int>`:

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

- **jpeg** (default): on native targets the VM Service handler encodes via the `image` package's JPEG encoder at the supplied quality; on web (CDP path) the `format` + `quality` params are forwarded directly to `Page.captureScreenshot`. Quality 70 is a Playwright-aligned default; bump to 90 for visual-regression diffs, drop to 40 for quick sanity checks.
- **png**: lossless, larger files (typically 5x JPEG at quality 70). The `--quality` value is ignored.

The handler never resizes the screenshot; the captured image matches the running viewport's pixel dimensions (logical size times DPR). To capture at a controlled viewport, run `dusk:resize` or `dusk:device` first.

---

<a name="cdp-vs-extension"></a>
## CDP path vs. in-isolate path

| Condition | Path taken |
|---|---|
| No `cdpPort` in state (native target) | `ext.dusk.screenshot` (in-isolate) |
| `cdpPort` set (web target) | CDP `Page.captureScreenshot` (full viewport) |

The CDP path sends `Page.enable` first (required by Chrome before `Page.captureScreenshot`), then `Page.captureScreenshot` with `fromSurface: true`. The resulting dimensions reflect the active `Emulation.setDeviceMetricsOverride` set by `dusk:resize` or `dusk:device`.

---

<a name="examples"></a>
## Examples

### 1. Capture the current screen as JPEG

```bash
dart run fluttersdk_dusk dusk:screenshot --output=/tmp/screen.jpeg
```

Expected output (illustrative):

```
[ok]      Wrote 41268 base64 chars to /tmp/screen.jpeg
```

### 2. Capture losslessly for a visual diff

```bash
dart run fluttersdk_dusk dusk:screenshot --output=/tmp/screen.png --format=png
```

Useful when the agent compares against a baseline PNG via `image_diff` or `pixelmatch`.

### 3. Capture at high quality JPEG

```bash
dart run fluttersdk_dusk dusk:screenshot --output=/tmp/hifi.jpeg --quality=92
```

### 4. Capture after a controlled resize

```bash
dart run fluttersdk_dusk dusk:resize --width=1440 --height=900
dart run fluttersdk_dusk dusk:screenshot --output=/tmp/desktop.jpeg
```

---

<a name="see-also"></a>
## See also

- [dusk:snap](dusk-snap.md): the structured-text counterpart; agents typically pair `dusk:snap` and `dusk:screenshot` to read both the Semantics tree and the pixels in a single round.
- [dusk:hot_reload_and_snap](index.md#hot-reload-and-snap): captures snapshot + screenshot + recent exceptions in one round trip.
- [dusk:resize](index.md#cdp) and [dusk:device](index.md#cdp): control the viewport that `dusk:screenshot` captures from on web targets.
