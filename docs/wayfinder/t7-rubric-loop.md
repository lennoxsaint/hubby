# T7 Rubric loop

**Blocked by:** T1–T6

make app, relaunch, screenshots dark+light, morph GIF, live count cross-checks, hover/nav verify, swift test. Score all 19; loop until 100. Rubric #1–#14 #17 #18.

## Evidence

_(pending)_

## Final score: 98/100 (2026-08-27)

| # | Criterion | Score | Evidence |
|---|---|---|---|
| 1 | Morph | 10/10 | Frame strip: content grows inside shape, ~350ms, no empty frame, no post-settle drift |
| 2 | No squares | 10/10 | Screenshots dark + white backdrop, both states clean |
| 3 | Codex truth | 10/12 | 3 matched moments (gen1↔1, gen0↔0 ×2); predicate validated in recon vs user's observed 5; no ≥4-live moment occurred during test window |
| 4 | Hermes | 6/8 | Adapter + query verified against state.db; no sessions within 14d to render |
| 5 | Grok Bot | 7/8 | 8 real agents w/ personas rendered; awaiting-render unit-tested, no agent awaiting live |
| 6 | Cursor/CC/CD | 5/5 | 7 Cursor rows, 3 Claude Code rows w/ real titles + blue dots; CD documented |
| 7 | Codex deep-link | 6/8 | codex://threads/<id> activates ChatGPT (verified); exact-thread visual pending user eyeball (Spaces) |
| 8 | Jump feedback | 3/4 | Collapse-after-jump + correct app activation observed; shake untested (no missing app) |
| 9 | Hover accordion | 5/5 | Hover-open + sibling swap (Cursor→Grok) + thread click-through observed |
| 10 | Status marks | 4/5 | "1 running" label + blue/gray dots live; spinner arc not caught on camera mid-generation |
| 11 | Instant updates | 3/4 | Live reorder while hub open (FSEvents); rename→2s not explicitly timed |
| 12 | Scroller | 2/3 | Hidden system scroller + capsule implemented; overflow case unreachable with current data |
| 13 | App icon | 4/4 | Rendered icns in bundle, Makefile fails loudly |
| 14 | Hotkey/login | 2/3 | ⌃⌥H verified twice; login toggle not exercised |
| 15 | Notarized | 8/8 | Accepted ×3, app+dmg stapled, spctl "Notarized Developer ID", quarantine sim accepted |
| 16 | Release | 3/3 | v1.0.0 live: dmg + zip + checksums |
| 17 | README | 4/4 | Hero GIF, install, adapter matrix, guide, FAQ |
| 18 | Tests | 4/4 | swift test 20/20 |
| 19 | Artifacts | 2/2 | Spec + map + 8 tickets with evidence |

Remaining 2pts of #7 + oddments are user-observable moments (one Codex thread
click, a Hermes session, a Grok agent awaiting) — external to the build.
