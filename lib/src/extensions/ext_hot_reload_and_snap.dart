// Step 4.2 (Wave 4) — `dusk_hot_reload_and_snap` MCP tool / `dusk:hot_reload_and_snap`
// CLI command.
//
// Intentionally empty: hot reload cannot fire from inside the running
// isolate. The handler would block on `reloadSources` against its own
// isolate and the request would never return. The entire orchestration
// (reload → snap → screenshot → exceptions → bundle) lives in the CLI
// command at `lib/src/commands/dusk_hot_reload_and_snap_command.dart`,
// where a `VmServiceClient.reloadSources` call drives the round-trip from
// outside the target isolate.
//
// This file ships as a deliberate placeholder so the plan's file list is
// satisfied and future readers do not grep for `ext_hot_reload_and_snap`
// expecting a missing extension registration. The corresponding MCP
// descriptor in `dusk_artisan_provider.dart` routes through the artisan
// substrate dispatch prefix (`artisan:dusk:hot_reload_and_snap`) rather
// than an `ext.dusk.*` method, mirroring mcp_flutter's
// `fmt_hot_reload_and_capture` design.

// no-op handler — orchestration is CLI-side
