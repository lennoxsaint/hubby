# Contributing to Hubby

Thanks for wanting to help! Start with [AGENTS.md](AGENTS.md) — it holds the
ground rules (read-only on other apps' data, native-only, graceful
degradation, essentially no network) and a long list of hard-won UI gotchas.
Those rules aren't suggestions; PRs that break them won't merge.

## The main contribution surface: adapters

Hubby learns about a new agent app through one file conforming to
`AgentSource` (`Sources/Hubby/Core/AgentSource.swift`). The recipe lives in
AGENTS.md ("Adding an adapter"):

1. `Sources/Hubby/Adapters/<App>Source.swift` conforming to `AgentSource`.
2. Parse defensively — wrap decoding in `try?`, return `[]` on failure,
   degrade to running-state detection when the store is unreadable.
3. Read databases through `Core/SQLiteReader` (never lock a live WAL).
4. Add fixture files + a parser test under `Tests/HubbyTests`.
5. Register in `ThreadStore.defaultSources()`.

Open an [adapter request](../../issues/new?template=adapter-request.yml)
first if you want a sanity check on where the app keeps its session state.

## Building and testing

```sh
swift build          # debug build
swift test           # the whole suite — must pass; CI runs exactly this
make run             # release bundle in dist/ and launch it
```

Parser logic must be testable from fixtures without the live filesystem.
UI changes are verified manually (launch + screenshot) — no UI test
scaffolding, please.

## Style

- Follow the style of the file you're in; no broad reformatting.
- One file per adapter; split any file that grows past ~300 lines.
- Comments state constraints the code can't show — not narration.
- Keep the version out of source: it lives in the `VERSION` file only.

## Releases (maintainer)

Bump `VERSION`, add a CHANGELOG section, push a matching `v*` tag —
`.github/workflows/release.yml` signs, notarizes, and publishes.
