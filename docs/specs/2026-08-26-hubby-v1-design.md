# Hubby v1.0 design spec — 26 Aug 2026

> Process note: Lennox asked for the /to-spec + /wayfinder + /to-tickets skills; those are
> manual-invocation-only, so this spec and the wayfinder docs use the same artifact shapes
> in a plain format. Run /wayfinder later if the formal process is wanted.

## Problem statement

Builders running several agent super-apps at once (ChatGPT/Codex, Claude Code, Cursor,
Hermes, Grok Bot) lose track of which agents are generating, which are finished, and —
worst — which are silently **waiting on them**. Hubby v0.2 shows threads but: counts are
wrong (Codex source covers 0.3% of threads), two apps are running-state stubs, thread
taps don't navigate anywhere, the expand animation is visibly two animations, and paint
artifacts (squares) undermine the "invisible desk pet" feel. It also isn't installable by
anyone but Lennox.

## Solution (user's perspective)

A floating orb that morphs — one continuous spring — into a frosted hub listing every
agent app, ordered by recency. Real thread titles everywhere. A spinner means "generating
right now" (verified against each app's actual store), a blue dot "recently active", gray
"idle", and an amber pulse means **"this agent needs you"** (Grok Bot's
awaitingUserResponse, surfaced nowhere else on macOS). Hover an app row and its threads
unfurl; click a Codex thread and ChatGPT opens **that thread** (codex:// deep link).
⌃⌥H summons the hub from anywhere. Distributed as a signed, notarized DMG from GitHub
Releases that thousands can install with zero Gatekeeper friction.

## Data contracts (verified 26 Aug 2026, this machine)

| Source | Store | Liveness predicate | Names |
|---|---|---|---|
| Codex (ChatGPT.app + CLI) | `~/.codex/state_5.sqlite` threads registry + rollout jsonl | recency ≤120s AND rollout mtime ≤90s AND last `task_started` > last `task_complete` in 64KB tail | threads.name → title → session_index.jsonl |
| Claude Code | `~/.claude/projects/**/*.jsonl` | mtime window | first user message |
| Hermes | `~/.hermes/state.db` sessions | `ended_at IS NULL AND end_reason IS NULL` + recent activity | display_name → title |
| Grok Bot | `…/Grok Bot/sand-client-persistence/<base32>.blob` roster | lastActivityAt window; `awaitingUserResponse` ⇒ needs-you | name / title |
| Cursor | `…/Cursor/User/globalStorage/conversation-search.db` | updated_at window | title |
| Claude Desktop | none readable (cloud LevelDB) | app running | — |

Navigation: Codex `codex://threads/<state-id>` (only true per-thread route on the system);
all others activate the app with visible feedback + hub collapse; missing app ⇒ row shake.

## Seams (test boundaries)

Existing seams reused — no new ones:
1. **Pure parsers/mergers** (`JSONLParsers`, `CodexThreadMerge`, new `RolloutTail`,
   `HermesSource.parse`, `GrokBotSource.parse`) — fixture-driven `swift test`.
2. **`AgentSource` protocol** — each adapter independently degradable to running-state.
3. **Rendered app** — manual/scripted visual verification (screenshots, GIF, live count
   cross-checks against sqlite/blob ground truth).

## Acceptance

The 19-criterion / 100-point rubric in `docs/wayfinder/map.md`. Ship gate = 100/100 with
evidence, or documented external blocker.

## Non-goals (v1.0)

Per-thread navigation for Claude/Cursor/Hermes/Grok (no routes exist — verified);
Claude Desktop conversation reading (cloud-only); Sparkle auto-updates; Windows/Linux.
