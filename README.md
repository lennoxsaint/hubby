# 🟣 Hubby

**One tiny floating hub for every AI agent thread on your Mac.**

Hubby is a little orb that floats above everything — every app, every Space.
Tap it (or hit **⌃⌥H**) and it morphs into a frosted hub showing every agent
app on your machine, the threads running in each one, **which agents are
generating right now**, and — the part nothing else shows you — **which agents
are blocked waiting on you**.

![Hubby morphing from orb to hub](docs/assets/hubby-morph.gif)

Built for people who run ChatGPT/Codex, Claude Code, Cursor, Hermes, and
Grok Bot *at the same time* and keep losing track of which agent is doing
what, where.

## Install

Grab `Hubby-x.y.z.dmg` from [Releases](https://github.com/lennoxsaint/hubby/releases),
drag Hubby to Applications, launch. Signed + notarized — no Gatekeeper hoops.
Requires macOS 14+.

Or build from source:

```sh
git clone https://github.com/lennoxsaint/hubby && cd hubby
make run
```

## What it shows

- **Collapsed:** a 56pt draggable orb — a 3D-ish deck of your most recently
  active agent apps' icons, a green badge counting threads generating right
  now, an amber badge counting agents waiting on you. Snaps to screen edges,
  lives on every Space.
- **Expanded:** one row per agent app, ordered by activity. Hover a row and
  its threads unfurl (click works too). Each thread shows a live status mark:
  - ◠ **spinner** — generating right now (verified against the app's own store)
  - 🟠 **amber pulse** — agent is blocked waiting for you
  - 🔵 **blue dot** — active in the last two minutes
  - ⚪ **gray dot** — idle
- **Click a thread** to jump: Codex threads deep-link straight to that exact
  thread in the ChatGPT app (`codex://threads/…`); other apps activate with
  the hub collapsing behind you. Missing app? The hub shakes instead of
  silently doing nothing.
- **⌃⌥H** toggles the hub from anywhere. Menu bar icon has launch-at-login.

## Supported agent apps (v1.0)

| App | Threads | Liveness | How |
|---|---|---|---|
| Codex (ChatGPT desktop + CLI) | ✅ real | ✅ exact | `~/.codex` thread registry + rollout-tail turn detection |
| Claude Code | ✅ real | 🟡 recency | `~/.claude/projects/**/*.jsonl` session files |
| Grok Bot | ✅ real | ✅ needs-you | roster blobs incl. `awaitingUserResponse` |
| Hermes | ✅ real | ✅ open-session | `~/.hermes/state.db` (`ended_at IS NULL`) |
| Cursor | ✅ real | 🟡 recency | `conversation-search.db` |
| Claude Desktop | 🟡 running-state | — | conversations are cloud-backed; no readable local store |

The ChatGPT desktop app *is* the Codex app (bundle `com.openai.codex`), so
they share one row. Renames and new threads propagate in ~1s via a single
FSEvents watcher.

Everything is **local and read-only**: Hubby never writes to another app's
data and never touches the network. App icons are loaded at runtime from the
apps installed on your Mac — no logos ship in this repo.

## Add your own agent app (~60 lines)

Implement the `AgentSource` protocol (`Sources/Hubby/Core/AgentSource.swift`):
tell Hubby where your app's session store lives, how to parse a thread list,
and (optionally) how to deep-link. Register it in
`ThreadStore.defaultSources()`, add a fixture test, PR it. Rules in
`AGENTS.md`: read-only, parse defensively, degrade gracefully.

## FAQ

**Why does the count differ from what I "feel" is running?**
Hubby counts *verified* generation: for Codex it tails each thread's rollout
file and checks the last turn event; a crashed turn stops counting within 90
seconds. Recency-only apps (Claude Code, Cursor) use a 2-minute activity
window.

**Does it slow anything down?** Reads are tiny (tails, indexed queries,
one 126KB blob) and fire only when the agent apps actually write, debounced.

**Why can't it jump to an exact Cursor/Claude/Hermes thread?** Those apps
expose no per-thread URL route (we checked their bundles). The moment they
do, their adapters grow a real `jump`.

## Development

```sh
swift build   # debug build
swift test    # parser + merge tests
make app      # release bundle at dist/Hubby.app
make icon     # regenerate AppIcon.icns from packaging/make-icon.swift
```

Release engineering (`make sign` / `dmg` / `notarize ISSUER=…` / `release`)
is in the Makefile.

## License

MIT. Do fun things with it.
