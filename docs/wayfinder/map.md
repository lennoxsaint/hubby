# Wayfinder map — Hubby v1.0 (local-markdown tracker)

## Destination

Hubby v1.0 on GitHub Releases: signed + notarized DMG, 100/100 on the rubric below with
recorded evidence, README worthy of a viral X launch.

## Notes

- Execution is carried in-map (Lennox's directive: loop until everything works end-to-end).
- Spec: [docs/specs/2026-08-26-hubby-v1-design.md](../specs/2026-08-26-hubby-v1-design.md)
- Tickets live beside this file; each holds its own evidence log.
- AGENTS.md rules bind: read-only on other apps' data, native only, graceful degradation.

## Tickets

| Ticket | Blocked by |
|---|---|
| [T1 One smooth morph + kill squares](t1-morph-and-paint.md) | — |
| [T2 Codex truth via rollout tail](t2-codex-truth.md) | — |
| [T3 Hermes + Grok Bot real adapters](t3-hermes-grok-adapters.md) | — |
| [T4 Status marks + waiting-on-you](t4-status-marks.md) | T2, T3 |
| [T5 Hover accordion + real navigation](t5-hover-navigation.md) | T1 |
| [T6 Scroller, app icon, hotkey, login item](t6-polish-identity.md) | T1 |
| [T7 Rubric loop: verify live, score, iterate](t7-rubric-loop.md) | T1–T6 |
| [T8 Sign, notarize, DMG, Release, README](t8-release.md) | T7 |

## The rubric (ship gate: 100/100)

| # | Criterion | Pts | Measurement |
|---|---|---|---|
| 1 | Single smooth morph | 10 | GIF: no empty-panel frame, settles <600ms, zero post-settle drift |
| 2 | Zero square artifacts | 10 | 2x screenshots dark+light, both states: outside-shape pixels = wallpaper |
| 3 | Codex count truth | 12 | Hubby count == ground-truth script ×3 moments (one ≥4 live); titles match sidebar |
| 4 | Hermes real threads | 8 | Titles real; running count matches `ended_at IS NULL` + activity |
| 5 | Grok Bot real threads | 8 | Rows match roster blob; awaitingUserResponse → amber "needs you" |
| 6 | Cursor + Claude Code rows | 5 | Real titles/recency; Claude Desktop documented running-state |
| 7 | Codex deep-link jump | 8 | Thread click opens THAT thread in ChatGPT (×2 threads) |
| 8 | Jump feedback everywhere | 4 | Right app activates, hub collapses, missing app shakes |
| 9 | Hover accordion | 5 | Opens ≤200ms, siblings close, threads clickable |
| 10 | Status marks | 5 | Spinner only on truly-generating (vs ground truth); boundary re-renders |
| 11 | Instant updates | 4 | Source rename/new thread reflected ≤2s (Codex + Hermes) |
| 12 | Custom scroller | 3 | System scroller hidden; capsule on scroll/hover only; no bounce when fits |
| 13 | App icon + branding | 4 | Real icns (Dock/Finder/menu bar); Makefile fails loudly if missing |
| 14 | Hotkey + login item | 3 | ⌃⌥H toggles anywhere; launch-at-login toggle works |
| 15 | Signed + notarized | 8 | codesign strict ✓ spctl ✓ stapler ✓ quarantined launch ✓ |
| 16 | Release published | 3 | v1.0.0 with DMG+zip+checksums+notes |
| 17 | README ship-quality | 4 | Hero GIF, install one-liner, adapter matrix, adapter guide, FAQ |
| 18 | Tests green | 4 | swift test ≥20 passing incl. RolloutTail/Hermes/Grok fixtures |
| 19 | Wayfinder artifacts | 2 | Map + spec + tickets with evidence |

## Decisions so far

- Spinner = generating, dot = done (Lennox, 26 Aug — dictation was inverted).
- Local markdown tracker (this dir); notarized distribution (cert XSL2TFT3P9 on disk).
- Codex liveness = rollout-tail predicate; thread_turns abandoned (covers 43/11,739 threads).
- Claude Desktop stays running-state (cloud LevelDB, unreadable by design).
- Per-thread deep link exists only for Codex (`codex://threads/<id>`); others activate-app.
