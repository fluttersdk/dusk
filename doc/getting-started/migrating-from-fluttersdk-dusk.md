# Migrating from fluttersdk_dusk

How to move an app that runs `fluttersdk_dusk` onto `tapir` and `dowel`, what `tapir:install` and `tapir:doctor` detect and print for you, and which command and tool names changed.

- [Quick Reference](#quick-reference)
- [Migration Steps](#migration-steps)
- [What tapir Detects](#what-tapir-detects)
- [Renamed Commands and Tools](#renamed-commands-and-tools)
- [Magic Apps](#magic-apps)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

Nothing is migrated automatically. The package, the repository, the barrels, the classes, the extensions, the tools and the environment variables all changed name, and the substrate under them is `dowel` instead of `fluttersdk_artisan`:

| Was | Is |
|:---|:---|
| `fluttersdk_dusk`, `fluttersdk_artisan` | `tapir`, `dowel` |
| `Dusk*` classes, `DuskArtisanProvider` | `Tapir*` classes, `TapirDowelProvider` |
| `ext.dusk.*` VM Service extensions | `ext.tapir.*` |
| `dusk_*` MCP tools | `tapir_*` |
| `dusk:*` CLI commands, `artisan:dusk:*` substrate commands | `tapir:*`, `dowel:tapir:*` |
| `DUSK_*` environment variables (`DUSK_FORCE_FRAMES`) | `TAPIR_*` (`TAPIR_FORCE_FRAMES`) |
| The perf zone key `#fluttersdk_interaction` | `#tapir_interaction` |
| `bin/fsa`, `.artisan/` | `bin/dowel`, `.dowel/` |
| The `fluttersdk` server in `.mcp.json` | The `dowel` server |
| `mcp__fluttersdk__dusk_*` in a Claude Code allow list | `mcp__dowel__tapir_*` |

<a name="migration-steps"></a>
## Migration Steps

Run them in this order. `tapir:install` can run at any point and prints what is still left, so a half-finished move is reported rather than failing inside a compiler error.

1. **Swap the packages.** Replace the old packages and rename what your code imports:

   ```bash
   flutter pub remove fluttersdk_dusk fluttersdk_artisan
   flutter pub add tapir dowel
   ```

   Every `package:fluttersdk_dusk/...` import becomes `package:tapir/tapir.dart`, or `package:tapir/cli.dart` in the code that runs on the plain Dart VM. Every `Dusk*` identifier becomes `Tapir*`, and `DuskArtisanProvider` becomes `TapirDowelProvider`.
2. **Move the state directories.** Follow the [dowel migration](https://anilcancakir.com/dowel/docs/getting-started/migrating-from-fluttersdk-artisan): move `.artisan/` to `.dowel/` and `~/.artisan/` to `~/.dowel/`, then delete `.dowel/plugins.json` and the `fluttersdk_*` records under `.dowel/installed/`.
3. **Delete the generated files.** Remove `bin/dispatcher.dart`, `bin/fsa`, `lib/app/_plugins.g.dart` and `lib/app/commands/_index.g.dart`. They import the old package and no longer compile, and an existing `bin/dispatcher.dart` is kept by the installer, so `bin/` stops analysing while it stays.
4. **Port your own commands.** In every file under `lib/app/commands/`, import `package:dowel/dowel.dart` instead of the old package and rename each `Artisan*` class to `Dowel*`.
5. **Delete the old MCP entry.** Remove the `fluttersdk` server from `.mcp.json` and from every client you registered by hand (`claude mcp remove fluttersdk`, the VS Code or Claude Desktop settings). It runs `./bin/fsa mcp:serve`, which step 3 deleted, and `mcp:install` adds `dowel` next to it instead of replacing it. Rename `dusk_*` to `tapir_*` in any saved allow list, prompt or script.
6. **Scaffold again and register.**

   ```bash
   dart run dowel install
   dart run dowel commands:refresh
   dart run tapir tapir:install
   dart run dowel plugin:install <package>
   dart run tapir mcp:install
   ```

   `dowel install` writes the dispatcher, the barrels and `bin/dowel`, `commands:refresh` registers your commands again, and `tapir:install` patches `lib/main.dart` and registers the plugin. Step 2 deleted `.dowel/plugins.json`, so the barrel now registers tapir alone: run `dart run dowel plugin:install <package>` once for every other plugin the app uses, or its commands are gone. `mcp:install` writes the `dowel` entry; reconnect your MCP client afterwards, because a stdio server is not reloaded on its own.
7. **Check the result.**

   ```bash
   dart run tapir start --device=chrome
   dart run tapir tapir:doctor
   ```

   The `fluttersdk_dusk leftovers` row of the doctor reads `none found` when the project is clean.

A Magic app has one more step: see [Magic Apps](#magic-apps).

<a name="what-tapir-detects"></a>
## What tapir Detects

`tapir:install` and `tapir:doctor` both look in the project root for what an install of `fluttersdk_dusk` left behind. The installer matters here because an old `bin/dispatcher.dart` also satisfies its own idempotency marker, so without the notice `dowel install` would be skipped in silence.

| It reports | When |
|:---|:---|
| `bin/dispatcher.dart (imports fluttersdk_artisan): delete it` | The file exists and mentions `fluttersdk_artisan`. |
| `bin/fsa: delete it` | The file exists. |
| `lib/app/commands/_index.g.dart: delete it` | The file imports `package:fluttersdk_artisan/` or `package:fluttersdk_dusk/`, or names a class the old package exported (`ArtisanCommand`, `ArtisanContext` and the rest dowel renamed) or `runArtisan`. The index `dowel install` and `commands:refresh` write is not reported. |
| `<path> (uses Artisan* classes): port it to the Dowel* classes` | A `.dart` file under `lib/app/commands/` (other than the index) mentions an `Artisan` class. One line per file. |
| `.mcp.json: delete the "fluttersdk" server entry` | The file has a `"fluttersdk"` key. |

**`tapir:install`** patches `lib/main.dart` first, then prints one warning that lists every finding, and goes on with its second phase. It deletes nothing and still exits `0`; it exits `1` only when `lib/main.dart` is missing:

```text
⚠ Leftovers from fluttersdk_dusk found:
  - bin/dispatcher.dart (imports fluttersdk_artisan): delete it
  - bin/fsa: delete it
  - lib/app/commands/_index.g.dart: delete it
  - lib/app/commands/deploy_command.dart (uses Artisan* classes): port it to the Dowel* classes
  - .mcp.json: delete the "fluttersdk" server entry
Then run `dart run dowel install`, `dart run dowel commands:refresh` and `dart run tapir tapir:install`.
```

Each line appears only when its file is there. With `bin/dispatcher.dart` still in place the installer does not scaffold `bin/dowel`, because its marker for that step is the dispatcher file.

**`tapir:doctor`** prints the same list as the last row, as a warning that never changes its exit code. A clean project prints:

```text
✓ fluttersdk_dusk leftovers: none found
```

and a project with leftovers prints `fluttersdk_dusk leftovers: found`, the same lines and the closing `Then run ...` sentence. See [tapir:doctor](../commands/tapir-doctor.md) for the other rows.

<a name="renamed-commands-and-tools"></a>
## Renamed Commands and Tools

Every command and tool takes the new prefix. Most keep their verb; these do not:

| Was | Is |
|:---|:---|
| `dusk:wait` | `tapir:wait_for` |
| `dusk:modal` | `tapir:dismiss_modals` |
| `dusk:resize`, `artisan:dusk:resize` | `tapir:resize_viewport`, `dowel:tapir:resize_viewport` |
| `dusk:device`, `artisan:dusk:device` | `tapir:device_profile`, `dowel:tapir:device_profile` |
| `dusk:dblclick`, `dusk_dblclick`, `ext.dusk.dblclick` | `tapir:double_click`, `tapir_double_click`, `ext.tapir.double_click` |
| `ext.dusk.find_by_label` | Removed. `tapir:find` and `tapir_find` cover it. |

Every other `dusk:<verb>` is `tapir:<verb>`, every other `dusk_<verb>` is `tapir_<verb>` and every other `ext.dusk.<verb>` is `ext.tapir.<verb>`. No alias is kept for any of them, so rename them in scripts, allow lists, `tapir:run` steps and CI configuration. See [Commands](../commands/index.md) and the [MCP tool reference](../mcp/tool-reference.md) for the full lists.

<a name="magic-apps"></a>
## Magic Apps

`magic_devtools` has to be a release built on tapir, one that ships `package:magic_devtools/tapir.dart`. A release that ships `MagicDuskIntegration` has no such library.

1. Remove `import 'package:magic_devtools/dusk.dart';` and the `MagicDuskIntegration.install()` call from `lib/main.dart`. The old installer added them, and `tapir:install` does not remove them.
2. Upgrade `magic_devtools` to a release built on tapir and run `flutter pub get`.
3. Run `dart run tapir tapir:install`. It adds `import 'package:magic_devtools/tapir.dart';` and, inside a `!kReleaseMode` block after `Magic.init(`, `MagicTapirIntegration.install()`. It adds nothing when a call to it is already in `lib/main.dart`, so check there is one and not two.

The installer reads `.dart_tool/package_config.json` to see which `magic_devtools` resolved. When it has no `tapir.dart` it skips the Magic lines and prints:

```text
⚠ Skipped MagicTapirIntegration: the installed magic_devtools has no tapir integration yet (no lib/tapir.dart). Upgrade magic_devtools to a release built on tapir, then rerun `dart run tapir tapir:install` (it is idempotent).
```

When `pub get` has not run, the parenthesis reads `(no lib/tapir.dart resolved; run `flutter pub get` if it has not run)`. The doctor says the same in its Magic row: `Magic detected, but the installed magic_devtools has no tapir integration yet; upgrade it to a release built on tapir, then rerun tapir:install`, or `Magic detected, but no magic_devtools resolved; add a release built on tapir to dev_dependencies, run flutter pub get, then rerun tapir:install`.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:---|:---|
| Running `tapir:install` before deleting `bin/dispatcher.dart`. | It patches `lib/main.dart`, prints the leftovers and skips `dowel install`. Delete the leftovers it names, then run the three commands it prints. |
| Adding the `dowel` entry with `mcp:install` while the `fluttersdk` entry is still in `.mcp.json`. | Both servers then run side by side. Delete the old entry first. |
| Keeping `mcp__fluttersdk__dusk_*` in an allow list. | The server key is `dowel` and the tools are `tapir_*`: use `mcp__dowel__tapir_*`. |
| Reading `none found` in the doctor as proof the move is complete. | The row looks for files only. It does not see `Dusk*` identifiers or a `MagicDuskIntegration` call left in your Dart code; the analyzer does. |
| An SDK older than the floor. | The package needs the Dart and Flutter versions in [Installation](installation.md#requirements); an app on an older SDK stays on the last `fluttersdk_dusk` release. |

<a name="related-documentation"></a>
## Related Documentation

- [Installation](installation.md): requirements and the wiring `tapir:install` writes.
- [tapir:install](../commands/tapir-install.md): the two phases and the leftover notice.
- [tapir:doctor](../commands/tapir-doctor.md): every row of the health check.
- [Magic integration](../plugins/magic-integration.md): what `MagicTapirIntegration` adds to a snapshot.
- [MCP setup](../mcp/setup.md): the `.mcp.json` entry and the reconnect after it changes.
- [dowel migration](https://anilcancakir.com/dowel/docs/getting-started/migrating-from-fluttersdk-artisan): the substrate half of the move.
