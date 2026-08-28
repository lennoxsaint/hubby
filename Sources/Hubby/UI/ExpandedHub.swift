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
    let onJump: (AgentSnapshot, AgentThread?) -> Void
    let onCollapse: () -> Void

    @State private var openApp: String?
    @State private var rowsHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollerVisible = false
    @State private var scrollerFadeTask: Task<Void, Never>?
    /// Drives the expand cascade; flipped once per insertion.
    @State private var revealed = false
    /// Thread id whose recap card is showing (500ms hover dwell).
    @State private var recapID: String?
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
    private let hoverTimer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    /// Seeding works because the hub view is freshly inserted on every
    /// expand — `State(initialValue:)` is honored each time.
    init(
        snapshots: [AgentSnapshot],
        initialOpenApp: String? = nil,
        onJump: @escaping (AgentSnapshot, AgentThread?) -> Void,
        onCollapse: @escaping () -> Void
    ) {
        self.snapshots = snapshots
        self.onJump = onJump
        self.onCollapse = onCollapse
        _openApp = State(initialValue: initialOpenApp)
    }

    private var scrollHeight: CGFloat {
        min(rowsHeight, HubbyMetrics.maxRowsHeight)
    }

    private var isScrollable: Bool { rowsHeight > HubbyMetrics.maxRowsHeight + 1 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(snapshots.enumerated()), id: \.element.id) { index, snapshot in
                        AppRow(
                            snapshot: snapshot,
                            isOpen: openApp == snapshot.id,
                            onToggle: {
                                withAnimation(.spring(duration: 0.3)) {
                                    openApp = openApp == snapshot.id ? nil : snapshot.id
                                }
                            },
                            onJump: onJump)
                        // Cascade: rows fall in one after another on expand.
                        // Animation is `value:`-scoped so hover, accordion,
                        // and reorders stay untouched; no per-row transition
                        // (it would re-fire on every reorder).
                        .opacity(revealed ? 1 : 0)
                        .offset(y: revealed ? 0 : 10)
                        .animation(
                            HubbyAnim.cascade.delay(0.05 + Double(min(index, 8)) * 0.045),
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
            wordmark
        }
        .onPreferenceChange(RowsHeightKey.self) { rowsHeight = $0 }
        .onAppear {
            if ProcessInfo.processInfo.environment["HUBBY_NOCASCADE"] != nil {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { revealed = true }
            } else {
                revealed = true
            }
        }
        .onChange(of: openApp) { recapID = nil } // its row is gone/moved
        .frame(width: HubbyMetrics.hubWidth)
        .overlayPreferenceValue(RecapAnchorKey.self) { anchors in
            recapOverlay(anchors: anchors)
                .background(GeometryReader { proxy in
                    Color.clear.onReceive(hoverTimer) { _ in
                        hoverTick(anchors: anchors, proxy: proxy)
                    }
                })
        }
        // Chrome (material, border, shadow) lives in MorphSurface so orb and
        // hub share one continuously morphing shape.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: HubHeightKey.self, value: proxy.size.height)
        })
    }

    /// The cursor in hub-content coordinates (top-left origin), or nil
    /// when it is outside the panel's visible content.
    private func mouseInHub() -> CGPoint? {
        guard let panel = NSApp.windows.first(where: { $0 is FloatingPanel && $0.isVisible })
        else { return nil }
        let mouse = NSEvent.mouseLocation
        let local = CGPoint(
            x: mouse.x - panel.frame.minX - HubbyMetrics.panelPadding,
            y: (panel.frame.maxY - mouse.y) - HubbyMetrics.panelPadding)
        guard local.x >= 0, local.x <= HubbyMetrics.hubWidth, local.y >= 0 else { return nil }
        return local
    }

    /// One 120ms hover tick: resolve the row under the cursor and drive the
    /// accordion (2 ticks ≈ 240ms) and the recap card (4 ticks ≈ 480ms).
    private func hoverTick(anchors: [String: Anchor<CGRect>], proxy: GeometryProxy) {
        let point = mouseInHub()
        let key = point.flatMap { p in
            anchors.first(where: { proxy[$0.value].contains(p) })?.key
        }
        if ProcessInfo.processInfo.environment["HUBBY_DEBUG"] != nil {
            FileHandle.standardError.write(Data(
                "tick p=\(point.map { "\(Int($0.x)),\(Int($0.y))" } ?? "-") key=\(key ?? "-") ticks=\(hoverTicks)\n".utf8))
        }
        if key != hoverKey {
            hoverKey = key
            hoverTicks = 0
            if recapID != nil, key != recapID {
                withAnimation(.easeOut(duration: 0.15)) { recapID = nil }
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
                withAnimation(.spring(duration: 0.3)) { openApp = appID }
            }
        } else if hoverTicks >= 4, recapID != key {
            withAnimation(.easeOut(duration: 0.15)) { recapID = key }
        }
    }

    /// The floating recap card, anchored by the hovered row's reported
    /// bounds. Placed below the row, flipped above near the hub's bottom,
    /// x-clamped to the hub; hit-testing is off throughout, so the panel's
    /// interactive rect never has to know it exists.
    @ViewBuilder
    private func recapOverlay(anchors: [String: Anchor<CGRect>]) -> some View {
        GeometryReader { proxy in
            if let id = recapID,
               let anchor = anchors[id],
               let thread = snapshots.flatMap(\.threads).first(where: { $0.id == id }) {
                let rect = proxy[anchor]
                let cardWidth: CGFloat = 270
                let estimatedHeight: CGFloat = 110
                let x = min(max(rect.minX, 6), proxy.size.width - cardWidth - 6)
                let below = rect.maxY + 4
                let y = below + estimatedHeight > proxy.size.height
                    ? max(rect.minY - estimatedHeight - 4, 6) : below
                RecapCard(thread: thread)
                    .frame(width: cardWidth, alignment: .leading)
                    .offset(x: x, y: y)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .allowsHitTesting(false)
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
            Text("Hubby")
                .font(HubbyGlass.wordmark)
                .foregroundStyle(.black.opacity(0.45))
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
    let onToggle: () -> Void
    let onJump: (AgentSnapshot, AgentThread?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    AppIconView(
                        info: snapshot.info,
                        size: 26,
                        dimmed: !snapshot.isRunning && snapshot.threads.isEmpty,
                        ring: RingCounts(snapshot: snapshot))

                    Text(snapshot.info.name)
                        .font(.system(.body, design: .rounded).weight(.medium))

                    if snapshot.runningCount > 0 {
                        Text("\(snapshot.runningCount) running")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(HubbyGlass.running)
                    }
                    if snapshot.needsYouCount > 0 {
                        Text("\(snapshot.needsYouCount) need you")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(HubbyGlass.needsYou)
                    }
                    if snapshot.unreadCount > 0 {
                        Text("\(snapshot.unreadCount) new")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(HubbyGlass.unread)
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
                .fill(.black.opacity(isOpen ? 0.045 : 0)))
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
                ForEach(snapshot.threads) { thread in
                    ThreadRow(thread: thread, onTap: { onJump(snapshot, thread) })
                }
            }
        }
        .padding(.leading, 26)
        .padding(.bottom, 6)
    }
}
