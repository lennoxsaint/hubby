# Hubby Roadmap

What's next after the command-center milestone (tiers, Approve/Choose
actuation, fidget orb). Ordered by intent, not by promise.

## 1. Capture suite — the orb becomes a shutter

The Hubby logo sits at the centre of the orb flower. Hovering (or clicking)
it reveals two icons:

- **Screenshot** — Screenshot-Pro style. Hover reveals three modes:
  capture the entire screen, capture just an app's window, or drag-select a
  region. Every shot lands with rounded corners on the subtle blush-pink
  glass background (the same glass as the orb) with a small cursive
  "Hubby" wordmark bottom-centre — framed, pretty, highly shareable.
- **Record** — ScreenStudio style. Hover reveals the same three scopes
  (screen / app / region); mic and camera toggle with one click on their
  icons.

### Thread-proof association

A capture usually exists to *prove something a thread did*. After a
recording/shot, Hubby offers the most likely thread (the one that was
generating or just finished on the recorded app) and attaches the capture
to it — proof captured in one gesture, routed to the reason it was taken.

### Auto-routing + default save location (quality of life)

- One-time setup: pick a default save location; every capture lands there
  automatically so it's always grabbable.
- Optional routing targets per capture: a platform (e.g. attach to a
  Threads/Slack draft), a specific thread, or the second brain inbox.
- Zero-friction default: click, capture, it's saved and framed. Routing is
  an offer, never a gate.

## 2. Actuation hardening

- **One-click plan approve**: the ExitPlanMode dialog's options are built
  dynamically, so v1 jumps instead of typing. To close the loop safely,
  read the raised terminal's visible text via AX at actuation time, find
  the row index of "Yes, manually approve edits", and navigate to exactly
  that row. Same technique would let the Choose card verify the on-screen
  option order before selecting.
- **Codex approvals**: when `approval_policy` ≠ `never`, rollouts emit
  `exec_approval_request` / `apply_patch_approval_request` events — detect
  them and extend the Approve pill to Codex.
- **Claude Code permission prompts** ("allow Bash?"): currently leave no
  trace in the session jsonl while pending. Revisit if a signal appears.
- **Nudge tuning**: today's guards (idle >2 min, nothing pending, exact tab
  raised) are conservative; watch real-world misfires before loosening.

## 3. Fidget polish

- True circular-scroll detection (angle tracking) if the vertical-scroll
  spin doesn't feel spinny enough in practice.
- Haptic tick per 60° step via NSHapticFeedbackManager.
