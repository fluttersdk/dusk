---
applyTo: '**'
---
# Documentation Sync

Every behavioral or interface change to this package touches code AND docs in the same change. Docs do not lag; CI does not enforce doc-sync directly (no doc-guard tests, per project decision), so the rule is operational: the agent who lands the code is the agent who lands the docs.

## Surface to doc map

| Code surface | Docs that must update |
|---|---|
| New `ext.tapir.*` extension in `lib/src/extensions/` | `README.md` VM Service surface list, `ARCHITECTURE.md` VM Service surface section, `CHANGELOG.md` `[Unreleased] Added`, `doc/commands/tapir-<verb>.md` (new file when shipping a CLI), `doc/mcp/tool-reference.md` (new section), `llms.txt` Commands list |
| New `DowelCommand` in `lib/src/commands/` | `README.md` Features table (32 -> 33), `ARCHITECTURE.md` CLI commands list, `CHANGELOG.md` `[Unreleased] Added`, `doc/commands/tapir-<verb>.md`, `llms.txt` Commands list |
| New `McpToolDescriptor` in `tapir_dowel_provider.dart:mcpTools()` | `README.md` Features table (31 -> 32), `ARCHITECTURE.md` MCP tools count line, `CHANGELOG.md` `[Unreleased] Added`, `doc/mcp/tool-reference.md` |
| Actionability gate change (new check, reorder, reason rewrite) | `README.md` 5-Gate row, `ARCHITECTURE.md` Actionability gate table, `CHANGELOG.md` `[Unreleased] Changed` with migration note, `doc/reference/actionability-gate.md`, `CLAUDE.md` Off-limits item 6 |
| FROZEN contract change (`TapirSnapshotEnricher`, `RefRegistry` public method, alpha-1 MCP name) | `CHANGELOG.md` `[Unreleased] Changed` flagged as breaking, `ARCHITECTURE.md` Frozen contracts section, `CLAUDE.md` Off-limits section, coordinated bump note in `CLAUDE.local.md` |
| Magic / wind integration change | `doc/plugins/magic-integration.md` or `doc/plugins/wind-integration.md`, plus a note in `CLAUDE.local.md` Sibling repos section |
| New device preset in `lib/src/cdp/device_presets.dart` | `README.md` CDP Device Emulation row, `ARCHITECTURE.md` CDP layer paragraph, `doc/commands/tapir-device.md` if present |
| Public API surface change (new export from `lib/tapir.dart`) | `ARCHITECTURE.md` Frozen contracts (FROZEN if widening the alpha-2 surface), `CHANGELOG.md` `[Unreleased] Added` |
| Skill content change under `skills/tapir/` | The matching `SKILL.md` and any reference files; bump the version line at the top |

When a change touches two or more surfaces, batch the doc edits into the same commit as the code change. Splitting code and doc into separate commits is allowed only when the doc lands first to set up a deprecation window.

## File format conventions

### `README.md`

Front-page marketing copy plus the feature table, badges, Quick Start, Compared-to table, and pointers to `doc/` and `anilcancakir.com/tapir`. Length budget: keep under 200 lines. Counts in the feature table are hard numbers (32 CLI, 31 MCP, 28 `ext.tapir.*`); update them every time `TapirDowelProvider.commands()` or `mcpTools()` changes shape.

### `ARCHITECTURE.md`

Internal reference for contributors. Carries the subsystem tree, boot flow, full CLI command list, MCP tools count, VM Service surface, Frozen contracts catalog (currently 10 items), Actionability gate table, RefRegistry token system, CDP layer notes, Hot reload flow. Do not duplicate marketing prose from README; ARCHITECTURE is the contributor's source of truth.

### `CHANGELOG.md`

Keep-a-Changelog 1.1.0 format (declared at line 5). Always has a `## [Unreleased]` section at the top; new bullets go there under one of `### Added`, `### Changed`, `### Deprecated`, `### Removed`, `### Fixed`, `### Security`. Empty subsections are omitted. Promote `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` on tag push; add a footer diff link (`[X.Y.Z]: https://github.com/anilcancakir/tapir/compare/v<prev>...vX.Y.Z`). Yanked releases append ` [YANKED]` to the heading.

### `doc/`

18 markdown files across 5 subdirectories: `commands/` (8 files: `index.md` plus 7 deep-dives), `getting-started/` (3), `mcp/` (3), `plugins/` (3), `reference/` (1). New page filenames follow `tapir-<verb>.md` under `commands/` or the existing convention under the other subdirs. `doc/api/` is the dartdoc output target and must stay in `.pubignore` and `.gitignore`. pub.dev does not surface `doc/**` automatically; it appears only via the docs website at `anilcancakir.com/tapir`.

### `llms.txt`

Follow the `llmstxt.org` spec: H1 = `# tapir`, single blockquote summary (one sentence, names the VM extension prefix + MCP tool count + actionability gate), then H2-delimited file lists (`## Docs`, `## MCP`, `## Source`, `## Optional`). Each list entry is `[label](url): note`. URLs point at `https://anilcancakir.com/tapir/docs/<path>.md` (the markdown sibling pattern). The `## Optional` section lists URLs the agent can skip for shorter context. Update whenever a new doc page lands; the file is the agent's structured entry point.

### `skills/`

When this package ships a skill under `skills/tapir/`, follow the same shape as `references/crumbs/skills/crumbs/`: `SKILL.md` at the root with frontmatter (`name`, `description`, `version`), plus `references/` subdir for tables-of-many-options that would inflate `SKILL.md` beyond ~200 lines. Update both the `SKILL.md` and the matching reference file on every surface change.

## Commit messages

Conventional Commits style: `feat(extensions): add ext.tapir.long_press handler`, `fix(actionability): off-viewport rect check ignored RTL viewports`, `docs(readme): bump VM Service surface count to 29`, `chore(ci): bump coverage floor to 85%`. Scopes: `extensions`, `commands`, `cdp`, `plugin`, `provider`, `tests`, `readme`, `architecture`, `changelog`, `docs`, `ci`, `pubspec`.

## Pre-publish checklist

Before pushing a tag matching `[0-9]+.[0-9]+.[0-9]+*` (which triggers `publish.yml`):

1. `## [Unreleased]` is promoted to `## [X.Y.Z] - YYYY-MM-DD` with footer link.
2. `pubspec.yaml` `version:` matches the tag.
3. `README.md`, `ARCHITECTURE.md`, `llms.txt` counts match `tapir_dowel_provider.dart` truth.
4. `dart pub publish --dry-run` is clean (exit 0; exit 65 means warnings, address them or document).
5. All four CI gates green on `develop`: format, analyze, test, coverage floor.
