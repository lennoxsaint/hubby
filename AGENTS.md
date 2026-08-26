# AGENTS.md — Hubby

Hubby is a tiny, always-on-top macOS widget that shows the AI agent threads running
across your machine (Claude Code, Codex CLI, ChatGPT app, Claude Desktop, Cursor,
Hermes, Grok Bot) and jumps to them on click. A circle that expands into a hub.

## Ground rules

1. **Read-only on other apps' data. Always.** Adapters may read other apps'
   session stores but must NEVER write to, lock, or migrate them. Go through
   `Core/SQLiteReader`: any database its owner writes while running (Codex,
   Cursor, Hermes — all WAL) opens plain `mode=ro` — `immutable=1` against a
   live WAL fails or reads empty — with a temp-copy fallback on open failure.
   `immutable=1` is only for genuinely static snapshots.
   If a store can't be read safely, degrade to running-state detection.
   Directory listings use path-based `contentsOfDirectory(atPath:)` + `stat`:
   the URL-enumerator variant can spin indefinitely on a directory that a
   live agent session is writing many times a second.
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
- Icon: `make icon`; sign/dmg/notarize/release targets in the Makefile
  (notarize needs `ISSUER=<App Store Connect issuer uuid>`)

## UI gotchas (learned the hard way)

- A gesture that sits UNDER a Material in this movable-by-background panel
  loses its mouseUp to AppKit's window-drag session — attach interaction
  modifiers OUTSIDE the chrome (see RootView's onTapGesture placement).
- `matchedGeometryEffect` displaced hit-testing in this borderless panel;
  don't reintroduce it without re-verifying clicks.
- The panel never resizes: it is always expanded-size and clear, with
  `PassthroughHostingView.hitTest` gating events to the visible content.
- `HUBBY_AUTOTEST=1` drives an expand/collapse cycle ~2.5s after launch for
  deterministic screenshots/recordings.

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
