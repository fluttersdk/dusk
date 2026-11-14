# Security Policy

## Supported Versions

Only the latest published version receives fixes.

## Reporting a Vulnerability

Report it through GitHub's private vulnerability reporting:
**[Open a private vulnerability report](https://github.com/anilcancakir/tapir/security/advisories/new)**

The report stays confidential until a fix is ready. Include the affected version, the platform, and the steps to reproduce.

## Scope

This policy covers the `tapir` package: `TapirPlugin`, the `ext.tapir.*` VM Service extensions, the `tapir:*` CLI commands, the `tapir_*` MCP tools and the `install.yaml` manifest. Issues in `dowel`, `wind_kit_diagnostics_contracts`, the Flutter SDK and the Dart VM Service belong to their maintainers.

tapir is a development tool. It drives a running Flutter app over the VM Service, and its extensions (`ext.tapir.evaluate`, `ext.tapir.press_key`, `ext.tapir.screenshot` among them) can run Dart in the app's isolate, type text, press keys and capture the screen, so anyone who can reach the VM Service of an app that has tapir installed can do the same. Install it only behind `if (!kReleaseMode)`, which keeps it in debug and profile builds and tree-shakes it out of a release build, and never ship a release build that registers `ext.tapir.*`. `--dart-define=TAPIR_DISABLE=1` makes `TapirPlugin.install()` skip registration in a build that must not expose the extensions. A report that needs a debug or profile build with the VM Service reachable by the attacker describes the intended trust boundary, not a vulnerability; one that shows an extension reachable in a release build is in scope.
