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
   The temp-copy cache is ONE dir per source db, refreshed in place and
   rate-limited for >64MB sources — a per-stamp dir scheme once piled up
   gigabytes of a 187MB Hermes db and stalled first paint for a minute.
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

- `NSWindow.performDrag(with:)` from a plain mouse-DOWN enters an
  event-tracking session with no mouse-up left to end it — the window
  glues to the cursor and the app reads as frozen. Only call it from
  `mouseDragged` after real movement. And never put an invisible drag
  band over interactive content: the ring's top band sat on priority
  row 1 and "clicking priority 1 froze the app". The top edge belongs
  to the priorities; the ring is left/right/bottom only.
- In global NSEvent monitors, NEVER trust `event.locationInWindow` for
  windowless events — on multi-display setups it can be measured against
  the wrong screen, making clicks INSIDE the hub read as outside (the
  hub collapsed on in-hub clicks). Use `NSEvent.mouseLocation`.
- Automation note: the panel SHIFTS on expand (`shiftToFitHub`) — never
  reuse pre-expand window coordinates for post-expand clicks; re-read
  the frame after the morph.
- Tap + drag on ONE view in this panel: `.onTapGesture` next to
  `.gesture(DragGesture)` never fires — the tap loses arbitration. Use
  `.simultaneousGesture(TapGesture())` beside the drag (movement fails the
  tap on real drags; suppress it explicitly while a drag is live). Also:
  `DragGesture(minimumDistance: 0)` stops delivering `onEnded` once
  dragged events intervene — keep a small minimumDistance and let the
  simultaneous tap own the click. (PrioritiesSection's numeral does both.)
- A gesture that sits UNDER the chrome in this movable-by-background panel
  loses its mouseUp to AppKit's window-drag session — attach interaction
  modifiers OUTSIDE the chrome (see RootView's onTapGesture placement).
  This predates the ink-glass swap (it's about the window, not the old
  Material) and still holds.
- The chrome background must stay scoped to the morphing shape (fills and
  strokes on the `RoundedRectangle` inside `MorphChrome`); a plain fill or
  post-hoc clip painted a square backing in this clear panel.
- `matchedGeometryEffect` displaced hit-testing in this borderless panel;
  don't reintroduce it without re-verifying clicks.
- The panel never resizes: it is always expanded-size and clear, with
  `PassthroughHostingView.hitTest` gating events to the visible content.
  Since the side-gutter cards, `panelSize` is hub + a card gutter EITHER
  side (`HubbyMetrics.contentInsetX` is the horizontal content inset —
  horizontal geometry must use it, not `panelPadding`). Hover cards float
  in the gutters; hitTest and the outside-click monitor widen to the live
  card rect (`PanelController.setCardRect`, pushed by the hub's hover
  tick). Cards must still fit inside `panelSize`.
- Hover cards CANNOT be rendered from inside the hub's own view tree:
  MorphChrome's `clipShape` swallows anything drawn beyond the hub's edge.
  The card renders in `CardOverlay`, attached in RootView AFTER the chrome
  (row anchors bubble up as preferences); `recapID` lives in RootView and
  the hub drives it through a binding. `CardGeometry.rect` is the single
  placement formula shared by layout, hover keepalive, and hitTest.
- The hover keepalive needs a corridor: the card sits across a gap from
  the hub, so the keepalive zone stretches from just inside the hub's edge
  to the card's far side (`keepAliveZone`) — without it, the cursor's
  transit across the gap dismisses the card before it can be clicked.
- `PassthroughHostingView.scrollWheel` gives the fan cycler first refusal;
  anything it declines (vertical scrolls, everything while expanded) MUST
  fall through to `super` or the hub's ScrollView dies.
- Accessibility (exact-jump window matching) needs no entitlement — only
  the user's TCC grant, and TCC keys it to the binary: a `swift build`
  debug run and `dist/Hubby.app` hold separate grants, so test the flow
  against `make app`'s bundle. Never present system UI from the
  nonactivating panel; the in-hub card + status-menu item are the pattern.
- `HUBBY_AUTOTEST=1` drives an expand/collapse cycle ~2.5s after launch for
  deterministic screenshots/recordings. `HUBBY_DEBUG=1` prints each jump's
  resolution/trust state to stderr.
- Any customized adapter behavior (like `jump(to:)`) MUST be declared as a
  protocol requirement on `AgentSource`, not just provided in the extension:
  extension-only methods are statically dispatched through the `AgentSource`
  existential, so every adapter override is silently ignored. This bug shipped
  once — the Codex deep link and AX window matching were dead until `jump`
  became a requirement.
- The outside-click global monitor receives CGEvent-posted (synthetic) clicks
  even when they land on our own window — AppKit only filters physical
  own-window events. The monitor must drop events inside the visible content
  rect or every automation/accessibility-tool click collapses the hub.
- SwiftUI `.onHover`/`.onContinuousHover`/`.help` on rows inside this
  borderless panel silently stop firing depending on key-window state —
  headers sometimes worked while thread rows never did. Hover is therefore
  driven by a 120ms poller in ExpandedHub (`hoverTick`) that hit-tests
  `NSEvent.mouseLocation` against the rows' `RecapAnchorKey` anchors. Two
  rules keep it sane: an accordion hover-open disarms until the cursor
  physically moves (rows shift under a stationary cursor and would cascade
  opens), and the recap card needs a 4-tick (~480ms) dwell.
- Replacing the signed binary can leave the AX grant half-alive:
  `AXIsProcessTrusted()` still true while every `kAXWindowsAttribute` copy
  fails. WindowLocator logs `windows-copy failed … err=` under HUBBY_DEBUG
  for exactly this; a fresh `make sign` (or toggling the grant off/on)
  restores it. Also: TCC changes (granting Accessibility) only take full
  effect for the AX APIs after the app relaunches — `AXIsProcessTrusted` may flip live while window
  enumeration still fails. Also: a binary launched from a terminal shell
  inherits the terminal's AX grant via responsible-process attribution, so
  the ungranted flow can only be tested via a `launchctl`/Finder launch.
- The floating prompt card is INTERACTIVE (options/controls are clickable),
  unlike the old display-only recap overlay. Two rules keep it workable:
  only the card's own frame takes hits (the overlay's GeometryReader has no
  hit surface), and the hover poller must keep the card alive while the
  cursor is inside its rect (`cardRect` is shared by layout and keepalive)
  — otherwise leaving the row to reach a button dismisses the card.
- Actuator guard contract (Keystrokes/PromptActuator): nothing may post a
  synthetic keystroke without, in order, (1) re-reading the session data
  and matching the exact pending `tool_use_id`, (2) raising the exact
  window, (3) confirming the target app is frontmost, and afterwards
  (4) confirming the answer appeared in the session data. Any failed step
  falls back to a plain jump. "Pending" for Claude Code means the tool_use
  has no later `tool_result` with its id AND no later message line — the
  answered record echoes the options back, so id correlation is mandatory.
- Keymap truth (read from Claude Code's own TUI source, not guessed): the
  plain AskUserQuestion QuestionView handles ONLY up/down/return — digit
  keys exist only in the preview variant, so digits silently no-op and a
  bare Return answers option 1. Navigate with Down×i then Return; a
  single-question, non-multiSelect selection submits the tool immediately.
  Plan-approval (ExitPlanMode) options are built DYNAMICALLY
  (clear-context / auto-mode / Ultraplan variants shift every index) — a
  blind sequence could select "bypass permissions", so plan approvals are
  never typed: the Approve pill exact-jumps to the dialog instead.
- Terminal tabs are NOT separate AX windows everywhere: Ghostty is ONE
  AXWindow (titled after the ACTIVE tab) holding an AXTabGroup of
  AXRadioButtons — one per tab, titled "✳ <session slug>". Landing on a
  thread means scoring the tab titles and AXPressing the winner, not just
  raising the window. WindowLocator returns the best score; only
  `score >= slugWeight` may be reported (or typed at) as an exact landing —
  cwd/hint signals can pick a *plausible* window that is the wrong tab.
- TextField editing works in this nonactivating panel (canBecomeKey is
  true, Spotlight-style): clicking a priorities line focuses it without
  activating the app. Don't "fix" the style mask or key behavior without
  re-verifying that editing still works.
- The swipe-away gesture is a LOCAL scroll-wheel NSEvent monitor installed
  by ExpandedHub (onAppear/onDisappear): the hub's ScrollView is
  vertical-only, so horizontal flicks over a thread row are free to claim.
  It decides ownership on the gesture's first real movement and then owns
  it through the momentum tail — the same discipline as the fan cycler.
- Codex "Automation: …" threads re-run on a schedule and will flood any
  recency-capped list; dedupe by name and rank below interactive threads
  (CodexThreadMerge), and fetch deep (64 rows) so real threads survive.
- `magnify(with:)` does reach the PassthroughHostingView in this
  nonactivating borderless panel; the override forwards to the panel's
  `onMagnify` and still calls super.

## Architecture

- `Core/Models.swift` — `AgentThread`, `AgentApp` value types.
- `Core/AgentSource.swift` — the adapter protocol. This is also the plugin
  contract for new agent apps: implement it, register in `ThreadStore.sources`.
- `Core/ThreadStore.swift` — observable store; FSEvents-driven refresh with
  a 30s fallback timer. Snapshots are decorated with read/unread state
  (`Core/ReadState.swift`) on the main actor before ordering.
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
