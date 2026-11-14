# Getting Started

Everything you need to add `tapir` to your project, capture your first
snapshot, and drive real user gestures from an AI agent or CLI session.

- [Pick your path](#pick-your-path)
- [What is tapir?](#what-is-tapir)
- [What problem does it solve?](#what-problem-does-it-solve)
- [When to use it](#when-to-use-it)
- [Requirements](#requirements)
- [High-level workflow](#high-level-workflow)
- [Related Documentation](#related-documentation)

<a name="pick-your-path"></a>
## Pick your path

- [**Installation**](installation.md): Wire TapirPlugin into a Flutter app and connect
  the MCP tools to your AI client.
- [**Quickstart**](quickstart.md): 3-step walkthrough from zero to driving the example
  app with snap, tap, and screenshot.
- [**Migrating from fluttersdk_dusk**](migrating-from-fluttersdk-dusk.md): Move an app
  that ran the predecessor package onto tapir and dowel.
- [**MCP setup**](../mcp/setup.md): Register the tapir MCP tools in Claude Code, Cursor,
  Windsurf, or any MCP-compliant client.
- [**Driving real apps: gotchas for agents**](driving-real-apps-gotchas.md): the
  recurring traps in real-app E2E sessions (stale refs, nested text fields,
  cumulative exceptions, stuck overlays) and the workaround each one has built in.

<a name="what-is-tapir"></a>
## What is tapir?

`tapir` is a Flutter E2E driver that gives an AI agent (or a CLI session)
eyes and hands over a running Flutter app. It works by registering a set of VM
Service extensions under the `ext.tapir.*` namespace during debug builds, then
exposing those extensions as MCP tools and CLI commands. The agent snaps a
Semantics YAML to identify widget references, then drives gestures, text input,
scrolling, and navigation against those references without any test instrumentation
in the production widget tree.

What sets it apart from `flutter_test`-based integration tests is that it operates
against the live running app, not a test-hosted widget. The agent sees the same UI
the user sees: real platform chrome, real routing, real auth state. This makes it
suitable for exploratory workflows where the agent does not know the widget tree in
advance and needs to discover it interactively.

<a name="what-problem-does-it-solve"></a>
## What problem does it solve?

Writing Flutter integration tests requires knowing the widget tree structure upfront,
hard-coding `find.byKey` / `find.byType` locators, and re-running the full suite
every time the UI changes. That works well for regression coverage but poorly for
exploratory agent-driven automation, where the agent needs to navigate an unfamiliar
UI, read its current state, and take adaptive actions.

`tapir` solves this by exporting the Semantics tree as a YAML snapshot
with stable `e<N>` (snapshot-frozen) and re-resolvable `q<N>` (minted by `tapir:find` or `tapir:observe`) ref
tokens. The agent reads the snapshot, locates the target element by semantic role or
label, and passes the ref token to an action extension. No test harness setup, no
build step, no `flutter drive` orchestration needed.

<a name="when-to-use-it"></a>
## When to use it

- **AI agent walkthroughs**: give Claude Code, Cursor, or Windsurf hands-on control
  of your Flutter app so it can inspect, fill forms, and verify flows during
  development or review.
- **Manual E2E scripting**: drive gestures and input from a terminal session without
  writing widget tests, useful for ad-hoc QA against a staging build.
- **Screenshot pipelines**: capture consistent screenshots of specific app states for
  documentation, design review, or visual regression baselines.
- **CI smoke checks**: run a small set of tapir commands in CI to confirm critical
  paths render without crash, complementing (not replacing) widget unit tests.

<a name="requirements"></a>
## Requirements

| Dependency | Minimum Version | Notes |
|:-----------|:----------------|:------|
| Dart       | `^3.13.0`       | The floor `material_ui` needs; Flutter 3.50 deprecates `package:flutter/material.dart` in its favour. |
| Flutter    | `>= 3.47.0`     | The Semantics APIs and `RepaintBoundary` render-tree walk used internally. |
| dowel | `^1.0.0` | Provides the MCP server, CLI framework, and `registerExtensionIdempotent`. |

`tapir` requires Flutter. It cannot run on a pure-Dart environment because
it synthesises pointer events against a live widget tree and walks the Semantics tree
at runtime. The `dowel` CLI is the recommended host for the MCP server
and all tapir CLI commands; install it before adding `tapir`.

<a name="high-level-workflow"></a>
## High-level workflow

The typical agent session follows three phases:

```
1. Capture snapshot   --  tapir_snap / tapir:snap
   Walks the Semantics tree and emits a YAML file with every
   visible widget, its ref token, role, label, bounds, and
   any enricher-contributed metadata (a `wind:` block, `magicRoute`, ...).

2. Identify a ref     --  read the YAML / tapir_find
   The agent scans the snapshot for the target widget by label
   or role, reads its ref token (e1, q3, ...).
   tapir_find re-resolves a token without a full re-snap.

3. Drive an action    --  tapir_tap / tapir_type / tapir_scroll / ...
   The agent passes the ref token to an action tool. The extension
   looks up the live element, checks the actionability gate,
   synthesises the event,
   and returns the result or a structured error.
```

After an action the agent re-snaps to observe the updated UI and continues the loop.
Screenshot requests can be inserted at any point to capture a PNG of the current
viewport.

<a name="related-documentation"></a>
## Related Documentation

- [Installation](installation.md): new here? Start with adding the package and wiring `TapirPlugin.install()`.
- [Quickstart](quickstart.md): already installed? Run a first snap, tap and screenshot.
- [Migrating from fluttersdk_dusk](migrating-from-fluttersdk-dusk.md): coming from the predecessor package? Start here.
- [Commands](../commands/index.md): every `tapir:*` command grouped by intent.
- [Reference: Actionability gate](../reference/actionability-gate.md): how tapir decides whether a widget is safe to act on.
