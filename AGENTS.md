# AGENTS.md — Hubby

Hubby is a tiny, always-on-top macOS widget that shows the AI agent threads running
across your machine (Claude Code, Codex CLI, ChatGPT app, Claude Desktop, Cursor,
Hermes, Grok Bot) and jumps to them on click. A circle that expands into a hub.

## Ground rules

1. **Read-only on other apps' data. Always.** Adapters may read other apps'
   session stores but must NEVER write to, lock, or migrate them. SQLite stores
   are opened read-only (`mode=ro&immutable=1`) or from a temp copy. If a store
   can't be read safely, degrade to running-state detection.
2. **Native only.** SwiftUI + AppKit. No Electron, no Tauri, no web views.
   Minimalism is the product.
3. **Graceful degradation is a feature.** Every `AgentSource` must work when its
   data source is missing, unreadable, or its format changes: fall back to
   `isRunning` + "Open app". Never crash on a parse failure.
4. **No network calls.** Hubby reads local files and local process state only.
   Nothing leaves the machine.
5. **Keep it small.** One file per adapter. UI stays in `Sources/Hubby/UI`.
   If a file grows past ~300 lines, split it.

## Commands (verified)

- Build: `swift build`
- Test: `swift test`
- Release + app bundle: `make app` (produces `dist/Hubby.app`)
- Run: `open dist/Hubby.app`

## Architecture

- `Core/Models.swift` — `AgentThread`, `AgentApp` value types.
- `Core/AgentSource.swift` — the adapter protocol. This is also the plugin
  contract for new agent apps: implement it, register in `ThreadStore.sources`.
- `Core/ThreadStore.swift` — observable store; polls sources every 5s.
- `Adapters/*.swift` — one adapter per agent app.
- `UI/` — `CollapsedOrb` (circle), `ExpandedHub` (rounded square), morph between
  them lives in `HubbyPanel`.
- `HubbyApp.swift` — NSApplication bootstrap, floating NSPanel, menu bar extra.

## Adding an adapter

1. Create `Adapters/<App>Source.swift` conforming to `AgentSource`.
2. Parse defensively: wrap all decoding in `try?`, return `[]` on failure.
3. Add fixture files + a parser test in `Tests/HubbyTests`.
4. Register the source in `ThreadStore.defaultSources()`.

## Testing

Parser logic must be testable without the live filesystem: parsers take
`Data`/`URL` inputs so tests can feed fixtures from `Tests/HubbyTests/Fixtures`.
UI is verified manually (launch + screenshot); don't add UI test scaffolding.
