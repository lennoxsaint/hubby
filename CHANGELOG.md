# Changelog

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
