import AppKit
import SwiftUI

/// Reports the hub's natural height so the panel can hug its content.
struct HubHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The expanded state: an ink-glass rounded square listing every agent app,
/// each expandable into a drop-down of its live threads. Height is dynamic:
/// the hub ends just below the last row, scrolling only past a cap.
struct ExpandedHub: View {
    let snapshots: [AgentSnapshot]
    /// The user's top-three list, pinned above the accordions.
    let priorities: PriorityStore
    /// Which side gutter the hover card floats in (screen-space choice).
    let cardSide: CardSide
    let onJump: (AgentSnapshot, AgentThread?) -> Void
    let onCollapse: () -> Void
    /// Answer a blocked prompt (nil = approve, else 0-based option).
    let onAnswer: (AgentSnapshot, AgentThread, Int?) -> Void
    let onTogglePin: (AgentSnapshot, AgentThread) -> Void
    /// Swipe-away: hide this thread until it shows new activity.
    let onDismiss: (AgentSnapshot, AgentThread) -> Void
    /// The visible card's frame in hub coordinates (nil = no card). The
    /// panel needs it: the card sits OUTSIDE the hub rect, so hitTest and
    /// the outside-click monitor must widen to it while it shows.
    let onCardRect: (CGRect?) -> Void

    @State private var openApp: String?
    @State private var rowsHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollerVisible = false
    @State private var scrollerFadeTask: Task<Void, Never>?
    /// Drives the expand cascade; flipped once per insertion.
    @State private var revealed = false
    /// Thread id whose recap card is showing (short hover dwell). Owned by
    /// RootView: the card itself renders in CardOverlay OUTSIDE the morph
    /// chrome (its clip would swallow a card drawn in the gutter).
    @Binding private var recapID: String?
    /// Poller-driven hover: the anchor key under the cursor + dwell ticks.
    /// NSTrackingArea/onHover proved unreliable in this borderless panel
    /// (silent no-fire depending on key status), so hover is derived from
    /// the mouse position against the rows' published anchors instead.
    @State private var hoverKey: String?
    @State private var hoverTicks = 0
    /// Where the cursor was when hover last opened an accordion. Opening
    /// shifts rows under a stationary cursor; requiring real movement
    /// before the next hover-open stops the open-cascade churn.
    @State private var lastHoverOpenPoint: CGPoint?
    /// Last card frame pushed to `onCardRect` (dedupes per-tick pushes).
    @State private var pushedCardRect: CGRect?
    /// The hub's clock: times and statuses tick live while it's open.
    @State private var now = Date()
    /// Swipe-away state: the row under a horizontal flick and how far it
    /// has slid. Scroll events come via a local NSEvent monitor — the
    /// hub's ScrollView is vertical-only, so leftward flicks are ours.
    @State private var swipeKey: String?
    @State private var swipeAccum: CGFloat = 0
    @State private var swipeArmed = false
    @State private var swipeDecided = false
    @State private var swallowMomentum = false
    @State private var swipeMonitor: Any?
    private let hoverTimer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()
    private let clockTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Seeding works because the hub view is freshly inserted on every
    /// expand — `State(initialValue:)` is honored each time.
    init(
        snapshots: [AgentSnapshot],
        priorities: PriorityStore,
        initialOpenApp: String? = nil,
        cardSide: CardSide = .right,
        recapID: Binding<String?> = .constant(nil),
        onJump: @escaping (AgentSnapshot, AgentThread?) -> Void,
        onCollapse: @escaping () -> Void,
        onAnswer: @escaping (AgentSnapshot, AgentThread, Int?) -> Void = { _, _, _ in },
        onTogglePin: @escaping (AgentSnapshot, AgentThread) -> Void = { _, _ in },
        onDismiss: @escaping (AgentSnapshot, AgentThread) -> Void = { _, _ in },
        onCardRect: @escaping (CGRect?) -> Void = { _ in }
    ) {
        self.snapshots = snapshots
        self.priorities = priorities
        self.cardSide = cardSide
        self.onJump = onJump
        self.onCollapse = onCollapse
        self.onAnswer = onAnswer
        self.onTogglePin = onTogglePin
        self.onDismiss = onDismiss
        self.onCardRect = onCardRect
        _openApp = State(initialValue: initialOpenApp)
        _recapID = recapID
    }

    /// Resolve an anchor key back to its thread.
    private func resolve(_ key: String) -> (snapshot: AgentSnapshot, thread: AgentThread)? {
        for snapshot in snapshots {
            if let thread = snapshot.threads.first(where: { $0.id == key }) {
                return (snapshot, thread)
            }
        }
        return nil
    }

    private var scrollHeight: CGFloat {
        min(rowsHeight, HubbyMetrics.maxRowsHeight)
    }

    private var isScrollable: Bool { rowsHeight > HubbyMetrics.maxRowsHeight + 1 }

    /// True when no adapter has produced a single thread — the first-run
    /// (or everything-disabled) look. Running-but-threadless apps count as
    /// empty too: rows of zeros read as broken, not calm.
    private var isEmptyState: Bool {
        snapshots.allSatisfy { $0.threads.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            PrioritiesSection(store: priorities)
            if isEmptyState {
                EmptyStateCard(apps: snapshots.map(\.info))
            } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        AppRow(
                            snapshot: snapshot,
                            isOpen: openApp == snapshot.id,
                            hoveredKey: hoverKey,
                            now: now,
                            rowOffset: { swipeDisplayOffset(for: $0) },
                            onToggle: {
                                withAnimation(HubbyAnim.accordion) {
                                    openApp = openApp == snapshot.id ? nil : snapshot.id
                                }
                            },
                            onJump: onJump,
                            onPillTap: { thread in pillTapped(snapshot, thread, key: thread.id) },
                            onTogglePin: { thread in onTogglePin(snapshot, thread) })
                        // Cascade: rows fall in one after another on expand.
                        // Animation is `value:`-scoped so hover, accordion,
                        // and reorders stay untouched; no per-row transition
                        // (it would re-fire on every reorder).
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 10)
                        .animation(
                            HubbyAnim.cascade.delay(0.03 + Double(min(index, 8)) * 0.022),
                            value: revealed)
                    }
                }
                .padding(8)
                .background(GeometryReader { proxy in
                    Color.clear
                        .preference(key: RowsHeightKey.self, value: proxy.size.height)
                        .preference(
                            key: ScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("hubbyRows")).minY)
                })
            }
            .coordinateSpace(name: "hubbyRows")
            // The NSScrollView backing paints an opaque window-background
            // rectangle unless explicitly hidden — the "block" behind the hub.
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(height: max(scrollHeight, 44))
            // A hard mid-row cut at the viewport edge reads as broken glass;
            // wash the last stretch out with the glass color so it reads as
            // "more below". An overlay, NOT .mask/.clipped — those killed
            // the thread rows' hover tracking (see AGENTS.md).
            .overlay(alignment: .bottom) {
                if isScrollable {
                    LinearGradient(
                        colors: [HubbyGlass.base.opacity(0), HubbyGlass.base],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: 30)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topTrailing) { scroller }
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                if offset != scrollOffset { recapID = nil } // anchor moved
                scrollOffset = offset
                guard isScrollable else { return }
                scrollerVisible = true
                scrollerFadeTask?.cancel()
                scrollerFadeTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    if !Task.isCancelled {
                        withAnimation(.easeOut(duration: 0.4)) { scrollerVisible = false }
                    }
                }
            }
            }
            wordmark
        }
        .onPreferenceChange(RowsHeightKey.self) { rowsHeight = $0 }
        .onReceive(clockTimer) { now = $0 }
        .onAppear {
            if ProcessInfo.processInfo.environment["HUBBY_NOCASCADE"] != nil {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { revealed = true }
            } else {
                revealed = true
            }
            now = Date()
            // Horizontal flicks over a thread row are swipe-away; the
            // vertical-only ScrollView never claims them, so a local
            // monitor picks them off before dispatch.
            swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                handleSwipeEvent(event) ? nil : event
            }
        }
        .onDisappear {
            if let swipeMonitor { NSEvent.removeMonitor(swipeMonitor) }
            swipeMonitor = nil
        }
        .onChange(of: openApp) { recapID = nil } // its row is gone/moved
        .frame(width: HubbyMetrics.hubWidth)
        // The tick loop only; the card renders in CardOverlay (RootView),
        // outside the chrome's clip. This GeometryReader draws nothing and
        // takes no hits.
        .overlayPreferenceValue(RecapAnchorKey.self) { anchors in
            GeometryReader { proxy in
                Color.clear.onReceive(hoverTimer) { _ in
                    hoverTick(anchors: anchors, proxy: proxy)
                }
            }
            .allowsHitTesting(false)
        }
        // Chrome (material, border, shadow) lives in MorphSurface so orb and
        // hub share one continuously morphing shape.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: HubHeightKey.self, value: proxy.size.height)
        })
    }

    /// The cursor in hub-content coordinates (top-left origin), or nil when
    /// it is outside the hub AND its card gutters — the card floats beside
    /// the hub, so the gutters count as hoverable ground.
    private func mouseInHub() -> CGPoint? {
        guard let panel = NSApp.windows.first(where: { $0 is FloatingPanel && $0.isVisible })
        else { return nil }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(
            x: mouse.x - panel.frame.minX - HubbyMetrics.contentInsetX,
            y: (panel.frame.maxY - mouse.y) - HubbyMetrics.panelPadding)
        guard local.x >= -HubbyMetrics.cardGutter,
              local.x <= HubbyMetrics.hubWidth + HubbyMetrics.cardGutter,
              local.y >= 0 else { return nil }
        return local
    }

    /// One 80ms hover tick: resolve the row under the cursor and drive the
    /// accordion (2 ticks ≈ 160ms) and the recap card (2 ticks ≈ 160ms).
    private func hoverTick(anchors: [String: Anchor<CGRect>], proxy: GeometryProxy) {
        let point = mouseInHub()
        let key = point.flatMap { p in
            anchors.first(where: { proxy[$0.value].contains(p) })?.key
        }
        if ProcessInfo.processInfo.environment["HUBBY_DEBUG"] != nil {
            FileHandle.standardError.write(Data(
                "tick p=\(point.map { "\(Int($0.x)),\(Int($0.y))" } ?? "-") key=\(key ?? "-") ticks=\(hoverTicks)\n".utf8))
        }
        pushCardRect(anchors: anchors, proxy: proxy)
        // While a card is showing, the cursor is allowed to leave the row
        // and travel INTO the card (it has clickable options/controls) —
        // including across the gap between the hub's edge and the card.
        // Dismissing on that transit would make the buttons unreachable.
        if let id = recapID, let point,
           let rect = cardRect(for: id, anchors: anchors, proxy: proxy),
           keepAliveZone(around: rect, proxy: proxy).contains(point) {
            return
        }
        if key != hoverKey {
            hoverKey = key
            hoverTicks = 0
            if recapID != nil, key != recapID {
                withAnimation(HubbyAnim.cardFade) { recapID = nil }
            }
            return
        }
        hoverTicks += 1
        guard let key else { return }
        if let appID = key.hasPrefix("app:") ? String(key.dropFirst(4)) : nil {
            let moved = lastHoverOpenPoint.map {
                abs(point!.x - $0.x) > 6 || abs(point!.y - $0.y) > 6
            } ?? true
            if hoverTicks == 2, openApp != appID, moved {
                lastHoverOpenPoint = point
                withAnimation(HubbyAnim.accordion) { openApp = appID }
            }
        } else if hoverTicks >= 2, recapID != key {
            withAnimation(HubbyAnim.cardFade) { recapID = key }
        }
    }

    /// The card rect grown by slop and stretched across the hub-to-card gap
    /// so the cursor's transit never lands on dead ground mid-crossing.
    private func keepAliveZone(around rect: CGRect, proxy: GeometryProxy) -> CGRect {
        var zone = rect.insetBy(dx: -6, dy: -6)
        switch cardSide {
        case .right:
            let bridge = proxy.size.width - 4 // just inside the hub's edge
            zone = CGRect(
                x: bridge, y: zone.minY,
                width: zone.maxX - bridge, height: zone.height)
        case .left:
            zone = CGRect(
                x: zone.minX, y: zone.minY,
                width: 4 - zone.minX, height: zone.height)
        }
        return zone
    }

    /// Report the live card frame (hub coordinates) whenever it changes so
    /// the panel can widen hit-testing to it — the card lives outside the
    /// hub rect and would otherwise be click-through.
    private func pushCardRect(anchors: [String: Anchor<CGRect>], proxy: GeometryProxy) {
        let rect = recapID.flatMap { cardRect(for: $0, anchors: anchors, proxy: proxy) }
        if rect != pushedCardRect {
            pushedCardRect = rect
            onCardRect(rect)
        }
    }

    /// The card frame for anchor key `id`, via the shared CardGeometry
    /// formula so layout (CardOverlay), keepalive, and hitTest agree.
    private func cardRect(
        for id: String, anchors: [String: Anchor<CGRect>], proxy: GeometryProxy
    ) -> CGRect? {
        guard let anchor = anchors[id], let entry = resolve(id) else { return nil }
        return CardGeometry.rect(
            rowRect: proxy[anchor],
            prompt: entry.thread.pendingPrompt,
            side: cardSide,
            hubSize: proxy.size)
    }

    /// A pill tap approves immediately (green) or reveals the options card
    /// (amber) — an Approve needs no extra step, a choice does.
    private func pillTapped(_ snapshot: AgentSnapshot, _ thread: AgentThread, key: String) {
        if thread.pendingPrompt?.kind == .approve {
            onAnswer(snapshot, thread, nil)
        } else {
            withAnimation(HubbyAnim.cardFade) { recapID = key }
        }
    }

    // MARK: swipe-away

    /// The visible slide of a row mid-swipe (leftward slides free, a
    /// rightward pull only rubber-bands a little).
    private func swipeDisplayOffset(for threadID: String) -> CGFloat {
        guard swipeKey == threadID else { return 0 }
        return swipeAccum < 0 ? swipeAccum : min(swipeAccum / 4, 10)
    }

    private static let swipeThreshold: CGFloat = 80

    /// One scroll event, ahead of dispatch. Returns true to consume.
    /// Mirrors the fan cycler's discipline: decide the gesture's owner on
    /// its first real movement, then own it to the end — momentum included.
    private func handleSwipeEvent(_ event: NSEvent) -> Bool {
        guard event.window is FloatingPanel else { return false }
        if event.momentumPhase != [] {
            if event.momentumPhase == .ended { swallowMomentum = false; return true }
            return swallowMomentum
        }
        switch event.phase {
        case .began:
            swipeDecided = false
            swipeArmed = false
            return false
        case .changed:
            if !swipeDecided {
                swipeDecided = true
                if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                   let key = hoverKey, !key.hasPrefix("app:"), resolve(key) != nil {
                    swipeArmed = true
                    swipeKey = key
                    swipeAccum = 0
                }
            }
            guard swipeArmed else { return false }
            swipeAccum += event.scrollingDeltaX
            if swipeAccum <= -Self.swipeThreshold, let key = swipeKey,
               let entry = resolve(key) {
                // Past the threshold: the row is gone. The store update
                // removes it; the hub just resets its gesture state.
                swipeKey = nil
                swipeAccum = 0
                if recapID == key { recapID = nil }
                withAnimation(HubbyAnim.accordion) {
                    onDismiss(entry.snapshot, entry.thread)
                }
            }
            return true
        case .ended, .cancelled:
            let consumed = swipeArmed
            if swipeArmed, swipeKey != nil {
                withAnimation(HubbyAnim.fanCycle) { swipeAccum = 0 }
            }
            swipeArmed = false
            swipeDecided = false
            swallowMomentum = consumed
            return consumed
        default:
            return false
        }
    }

    /// A minimal capsule thumb, drawn only while scrolling a capped list —
    /// the system scroller's track would puncture the frosted material.
    @ViewBuilder
    private var scroller: some View {
        if isScrollable {
            let viewport = max(scrollHeight, 44)
            let thumbHeight = max(viewport * viewport / rowsHeight, 24)
            let travel = viewport - thumbHeight - 8
            let progress = min(max(scrollOffset / (rowsHeight - viewport), 0), 1)
            Capsule()
                .fill(.black.opacity(0.28))
                .frame(width: 3, height: thumbHeight)
                .padding(.trailing, 3)
                .offset(y: 4 + travel * progress)
                .opacity(scrollerVisible ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    /// The signature: cursive "Hubby" at the bottom centre, subtle and
    /// translucent. It doubles as the in-hub collapse control (clicking
    /// outside the panel collapses too — there is no header).
    private var wordmark: some View {
        Button(action: onCollapse) {
            HStack(spacing: 5) {
                // The same octopus the user just clicked in the orb, now
                // settled by the wordmark — once the morph lands it shakes
                // its legs wide in an unmistakable burst of excitement.
                KeyframeAnimator(initialValue: CGFloat(0), trigger: revealed) { splay in
                    // The legs alone are ~1px of motion at this size, so the
                    // whole body hops up with them — that's what makes the
                    // excitement land at 15pt.
                    OctopusView(size: 15, splay: splay)
                        .scaleEffect(1 + 0.45 * max(splay, 0), anchor: .bottom)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(0, duration: 0.3)      // let the morph land
                        CubicKeyframe(1, duration: 0.13)     // legs FLING wide…
                        CubicKeyframe(-0.35, duration: 0.12) // …snap back in…
                        CubicKeyframe(0.85, duration: 0.12)  // …out again…
                        CubicKeyframe(-0.25, duration: 0.11) // …and in…
                        SpringKeyframe(0, duration: 0.45)    // …then settle
                    }
                }
                Text("Hubby")
                    .font(HubbyGlass.wordmark)
                    .foregroundStyle(.black.opacity(0.45))
            }
            .padding(.top, 1)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Collapse to orb")
    }
}

private struct RowsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AppRow: View {
    let snapshot: AgentSnapshot
    let isOpen: Bool
    let hoveredKey: String?
    /// The hub's ticking clock, threaded to rows for live times/statuses.
    let now: Date
    /// A row's live swipe-away slide (0 for everything not mid-swipe).
    let rowOffset: (String) -> CGFloat
    let onToggle: () -> Void
    let onJump: (AgentSnapshot, AgentThread?) -> Void
    let onPillTap: (AgentThread) -> Void
    let onTogglePin: (AgentThread) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    AppIconView(
                        info: snapshot.info,
                        size: 26,
                        dimmed: !snapshot.isRunning && snapshot.threads.isEmpty)

                    Text(snapshot.info.name)
                        .font(.system(.body, design: .rounded).weight(.medium))

                    // The one signal loud enough for a header: blocked on
                    // the human. Everything else (running, unread) lives in
                    // the drop-down — headers stay calm.
                    if snapshot.needsYouCount > 0 {
                        Text("\(snapshot.needsYouCount) need you")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(HubbyGlass.needsYou)
                    }

                    Spacer()

                    if !snapshot.threads.isEmpty {
                        Text("\(snapshot.threads.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The hub's hover poller reads this anchor to open the
            // drop-down on dwell (accordion); click still toggles.
            .anchorPreference(key: RecapAnchorKey.self, value: .bounds) {
                ["app:\(snapshot.id)": $0]
            }

            if isOpen {
                dropDown
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.black.opacity(isOpen ? 0.03 : 0)))
    }

    private var dropDown: some View {
        VStack(spacing: 0) {
            if snapshot.threads.isEmpty {
                Button {
                    onJump(snapshot, nil)
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.forward.app")
                        Text(snapshot.isRunning ? "Running — open app" : "Open app")
                        Spacer()
                    }
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                // Threads arrive pre-tiered (blocked → pinned → recent);
                // the hairline marks where the pinned tier ends.
                let divider = ThreadTiers.dividerIndex(snapshot.threads)
                ForEach(Array(snapshot.threads.enumerated()), id: \.element.id) { index, thread in
                    if index == divider {
                        Rectangle()
                            .fill(HubbyGlass.hairline)
                            .frame(height: 0.5)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                    }
                    ThreadRow(
                        thread: thread,
                        now: now,
                        hovered: hoveredKey == thread.id,
                        onTap: { onJump(snapshot, thread) },
                        onPin: { onTogglePin(thread) },
                        onPillTap: { onPillTap(thread) })
                    .offset(x: rowOffset(thread.id))
                    .opacity(1 - min(abs(rowOffset(thread.id)) / 160, 0.7))
                }
            }
        }
        .padding(.leading, 26)
        .padding(.bottom, 6)
    }
}
