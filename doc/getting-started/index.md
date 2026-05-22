# Getting Started

Everything you need to add `fluttersdk_dusk` to your project, capture your first
snapshot, and drive real user gestures from an AI agent or CLI session.

## Pick your path

- [**Installation**](installation): Wire DuskPlugin into a Flutter app and connect
  the MCP tools to your AI client.
- [**Quickstart**](quickstart): 3-step walkthrough from zero to driving the example
  app with snap, tap, and screenshot.
- [**MCP setup**](../mcp/setup): Register the dusk MCP tools in Claude Code, Cursor,
  Windsurf, or any MCP-compliant client.

## What is fluttersdk_dusk?

`fluttersdk_dusk` is a Flutter E2E driver that gives an AI agent (or a CLI session)
eyes and hands over a running Flutter app. It works by registering a set of VM
Service extensions under the `ext.dusk.*` namespace during debug builds, then
exposing those extensions as 31 MCP tools and 32 CLI commands. The agent snaps a
Semantics YAML to identify widget references, then drives gestures, text input,
scrolling, and navigation against those references without any test instrumentation
in the production widget tree.

What sets it apart from `flutter_test`-based integration tests is that it operates
against the live running app, not a test-hosted widget. The agent sees the same UI
the user sees: real platform chrome, real routing, real auth state. This makes it
suitable for exploratory workflows where the agent does not know the widget tree in
advance and needs to discover it interactively.

## What problem does it solve?

Writing Flutter integration tests requires knowing the widget tree structure upfront,
hard-coding `find.byKey` / `find.byType` locators, and re-running the full suite
every time the UI changes. That works well for regression coverage but poorly for
exploratory agent-driven automation, where the agent needs to navigate an unfamiliar
UI, read its current state, and take adaptive actions.

`fluttersdk_dusk` solves this by exporting the Semantics tree as a YAML snapshot
with stable `e<N>` (snapshot-frozen) and re-resolvable `q<N>` (find-minted) ref
tokens. The agent reads the snapshot, locates the target element by semantic role or
label, and passes the ref token to an action extension. No test harness setup, no
build step, no `flutter drive` orchestration needed.

## When to use it

- **AI agent walkthroughs**: give Claude Code, Cursor, or Windsurf hands-on control
  of your Flutter app so it can inspect, fill forms, and verify flows during
  development or review.
- **Manual E2E scripting**: drive gestures and input from a terminal session without
  writing widget tests, useful for ad-hoc QA against a staging build.
- **Screenshot pipelines**: capture consistent screenshots of specific app states for
  documentation, design review, or visual regression baselines.
- **CI smoke checks**: run a small set of artisan commands in CI to confirm critical
  paths render without crash, complementing (not replacing) widget unit tests.

## Requirements

| Dependency | Minimum Version | Notes |
|:-----------|:----------------|:------|
| Dart       | `>= 3.4.0`      | Records, sealed classes, class modifiers. |
| Flutter    | `>= 3.22.0`     | `RepaintBoundary` render-tree walk and Semantics APIs used internally. |
| fluttersdk_artisan | `^0.0.3` | Provides the MCP server, CLI framework, and `registerExtensionIdempotent`. |

`fluttersdk_dusk` requires Flutter. It cannot run on a pure-Dart environment because
it synthesizes pointer events against a live widget tree and walks the Semantics tree
at runtime. The `fluttersdk_artisan` CLI is the recommended host for the MCP server
and all dusk CLI commands; install it before adding `fluttersdk_dusk`.

## High-level workflow

The typical agent session follows three phases:

```
1. Capture snapshot   --  dusk_snap / dusk:snap
   Walks the Semantics tree and emits a YAML file with every
   visible widget, its ref token, role, label, bounds, and
   any enricher-contributed metadata (className, MagicRoute, ...).

2. Identify a ref     --  read the YAML / dusk_find
   The agent scans the snapshot for the target widget by label
   or role, reads its ref token (e1, q3, ...).
   dusk_find re-resolves a token without a full re-snap.

3. Drive an action    --  dusk_tap / dusk_type / dusk_scroll / ...
   The agent passes the ref token to an action tool. The extension
   looks up the live element, checks the actionability gate
   (enabled, non-zero-rect, on-viewport), synthesizes the event,
   and returns the result or a structured error.
```

After an action the agent re-snaps to observe the updated UI and continues the loop.
Screenshot requests can be inserted at any point to capture a PNG of the current
viewport.

## Next steps

- New here? Start with [Installation](installation).
- Already installed? Run the [Quickstart](quickstart).
