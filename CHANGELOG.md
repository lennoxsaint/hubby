# Changelog

## 1.1.0 — 2026-08-29

The calm release: a full visual quiet-down, a priorities queue, and the
open-source plumbing (CI releases, Homebrew tap, diagnostics).

- **Two-signal language**: shimmer = generating, amber = waiting on you.
  Rings, badges, dots-for-everything, rim glow, and sheen are gone — one
  flat blush-glass surface, dark ink, and exactly two colors that mean
  something.
- **Priorities queue + ledger**: three slots above the apps; ticking №1
  promotes everything up and appends the finished item (with timestamps
  and time-on-list) to a local `priority-history.jsonl`.
- **Fixed: clicking priority 1 froze the app** — the edge-drag ring's top
  band overlapped the row and a mouse-down drag session glued the window
  to the cursor. The ring is now left/right/bottom only and engages only
  on real movement. Also fixed: in-hub clicks collapsing the hub on
  multi-display setups, and the faint square halo around the orb on light
  desktops (stacked shadows).
- **Drag the hub by its edges** to move the board; the interior stays
  fully interactive.
- **Unified "generating"** across Claude Code, Cursor, and Grok threads —
  the same store-verified rule everywhere.
- **First-run empty state** explaining what Hubby watches for.
- **Menu bar grew up**: version line, per-adapter enable/disable, opt-in
  (off-by-default) update check against GitHub Releases, and "Report a
  Problem…" which writes a redacted debug bundle to your Desktop.
- **App version is now truthful** (1.0.0 shipped reporting 0.1.0):
  single-sourced from the `VERSION` file and stamped at build time.
- Releases are now built, signed, and notarized by CI on tag push;
  `brew install lennoxsaint/tap/hubby` is a supported install path.

## 1.0.0 — 2026-08-26

First public release.

- **One smooth morph**: constant-size clear panel with hit-test passthrough;
  a single spring animates the orb ↔ hub shape (no more window-resize seam).
- **True Codex counts**: liveness now comes from each thread's rollout tail
  (`task_started` vs `task_complete`), covering legacy + subagent +
  automation threads; `thread_history` (0.3% coverage, crash-sticky) dropped.
- **Real adapters for Hermes and Grok Bot** — Hermes `state.db` sessions,
  Grok Bot roster blobs with the **"needs you"** state (amber pulse + badge).
- **Real navigation**: Codex threads deep-link via `codex://threads/<id>`;
  Claude Code activates the terminal actually running; every jump collapses
  the hub; a missing app shakes instead of silently no-oping.
- Hover accordion drop-downs, custom capsule scroller, four-state status
  marks (spinner / needs-you / active / idle).
- Real app icon, ⌃⌥H global hotkey, launch-at-login, signed + notarized DMG.
- Fixed: gray square artifacts (scroll background, clipped shadows, unclipped
  icon fan), Cursor adapter reading empty against a live WAL, adapter hang
  when a live Claude Code session writes at high frequency.

## 0.2 — 2026-08-26

Real Codex data, real app icons, transparent panel, dynamic hub height.

## 0.1 — 2026-08-26

First orb. Claude Code + Cursor + running-state adapters.
