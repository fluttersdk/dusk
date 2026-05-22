<!-- Generated for fluttersdk_dusk v0.0.1 publish-prep (2026-05-20). -->

# CLAUDE.md

This file provides agent-level guidance to Claude Code when working in this repository.
For the full architecture reference, public contracts, and Off-limits section see `CLAUDE.md` at the package root.

## Commands

| Command | When |
|---|---|
| `flutter test` | Run all tests. Baseline at 0.0.1 release: 517 passing / 93 pre-existing failures accepted (see CHANGELOG `### Risks Accepted`; test stabilization is a tracked follow-up). |
| `flutter test --coverage` | Generate `coverage/lcov.info` for the 80% gate. |
| `dart format lib/ test/ bin/` | Format. Must produce no diff. |
| `dart analyze` | Static analysis. Zero issues required across `lib/` and `test/`. |
| `dart run fluttersdk_dusk <cmd>` | Run a `dusk:*` command standalone via the Flutter-free CLI wrapper. |
| `dart pub publish --dry-run` | Validate publish archive. Target under 500 KB compressed. |

## Golden Rules (apply on every change)

1. **Doc sync (`doc/`)**. If a code change touches behavior described in `doc/**/*.md`, update the relevant doc page in the same change. New feature without an existing page: add one under `doc/{getting-started,commands,mcp,reference}/<name>.md`.
2. **Skill sync**. When dusk ships a skill under `skills/`, keep the matching `SKILL.md` and reference files in sync with every surface change (commands, MCP tools, VM Service extensions, enricher API).
3. **Test coverage stays at or above 80%**. Current line coverage is 79.4% (`coverage/lcov.info`). Run `flutter test --coverage` after behavioral changes; verify via `awk -F: '/^LF:/{lf+=$2} /^LH:/{lh+=$2} END{printf "%.2f%%\n", (lh/lf)*100}' coverage/lcov.info`. Drops below 80% block the change. (Coverage stabilization is tracked in a follow-up plan.)
4. **README sync**. When a change is significant enough for the package landing page (new command, new MCP tool, new VM extension, breaking change), update `README.md`. Use descriptive link labels pointing at `https://fluttersdk.com/dusk/...` paths.
5. **CHANGELOG always under `[Unreleased]`**. Every behavioral or interface change lands an entry under `## [Unreleased]` in `CHANGELOG.md`. Categories: `Added` / `Changed` / `Fixed` / `Removed`. Promote to a dated section on `dart pub publish`.
6. **Green gate plus TDD**. `dart format lib/ test/ bin/` produces zero diff, `dart analyze` returns zero issues, `flutter test` returns all green. TDD red-green-refactor for behavioral changes: write the failing test first, then the implementation that turns it green. Reverting the implementation must turn the test red again.

## Path-scoped rules

- `.github/instructions/extensions.instructions.md` (paths: `lib/src/extensions/**`, `test/src/extensions/**`): VM Service handler registration discipline, actionability gate routing, error-response shape.
- `.github/instructions/tests.instructions.md` (paths: `test/**`): test layout mirror, RefRegistry teardown, fixture naming, TDD red-green-refactor specifics.

Read those files when touching the matching paths.
