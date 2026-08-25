# 🟣 Hubby

**One tiny floating hub for every AI agent thread on your Mac.**

Hubby is a little circle that floats above everything — every app, every Space.
Tap it and it blooms into a rounded-square hub showing the agent apps on your
machine and the threads currently running in each one. Tap a thread and Hubby
jumps you straight to it.

Built for people who run ChatGPT, Claude Code, Claude Desktop, Cursor, Codex,
Hermes, and Grok Bot *at the same time* and keep losing track of which agent is
doing what, where.

## Form factor

- **Collapsed:** a 56pt draggable orb showing the icons of your connected agent
  apps and a badge with the count of active threads. Snaps to screen edges.
  Always on top, on every Space — like a desk pet, but useful.
- **Expanded:** tap the orb and it morphs into a frosted rounded square.
  One row per agent app. Tap a row → a drop-down of its live threads with
  last-activity time and an active/idle dot. Tap a thread → jump to it.

## Supported agent apps (v0.1)

| App | Thread list | How |
|---|---|---|
| Claude Code | ✅ real | reads `~/.claude/projects/**/*.jsonl` session files |
| Codex CLI | ✅ real | reads `~/.codex/sessions/**/*.jsonl` rollouts |
| ChatGPT app | 🟡 running-state | local conversation store is encrypted — titles on the roadmap |
| Cursor | ✅ real | reads `conversation-search.db` (read-only, immutable SQLite) |
| Claude Desktop | 🟡 running-state | app running indicator + open |
| Hermes | 🟡 running-state | app running indicator + open |
| Grok Bot | 🟡 running-state | app running indicator + open |

Everything is **local and read-only**: Hubby never writes to another app's data
and never touches the network.

## Install / run

```sh
git clone https://github.com/lennoxsaint/hubby && cd hubby
make app
open dist/Hubby.app
```

Requires macOS 14+ and Xcode command line tools. The app is unsigned; first
launch may need right-click → Open.

## Adding your own agent app

Adapters are ~60-line Swift files. Implement the `AgentSource` protocol
(`Sources/Hubby/Core/AgentSource.swift`), register it in
`ThreadStore.defaultSources()`, add a fixture test. See `AGENTS.md` for the
rules (read-only, defensive parsing, graceful fallback).

## Development

```sh
swift build   # debug build
swift test    # parser tests
make app      # release bundle at dist/Hubby.app
```

## License

MIT. Do fun things with it.
