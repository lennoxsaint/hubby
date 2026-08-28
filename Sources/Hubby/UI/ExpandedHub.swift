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
            header
            Divider().opacity(0.4).padding(.horizontal, 14)
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
                            onHoverOpen: {
                                withAnimation(.spring(duration: 0.3)) {
                                    openApp = snapshot.id // accordion: siblings close
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
            .overlay(alignment: .topTrailing) { scroller }
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
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
        .onPreferenceChange(RowsHeightKey.self) { rowsHeight = $0 }
        .onAppear { revealed = true }
        .frame(width: HubbyMetrics.hubWidth)
        // Chrome (material, border, shadow) lives in MorphSurface so orb and
        // hub share one continuously morphing shape.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: HubHeightKey.self, value: proxy.size.height)
        })
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
                .fill(.white.opacity(0.35))
                .frame(width: 3, height: thumbHeight)
                .padding(.trailing, 3)
                .offset(y: 4 + travel * progress)
                .opacity(scrollerVisible ? 1 : 0)
                .allowsHitTesting(false)
        }
    }

    /// The whole header collapses the hub — no dedicated button needed
    /// (clicking outside the panel collapses it too).
    private var header: some View {
        Button(action: onCollapse) {
            HStack {
                Text("Hubby")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
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
    let onHoverOpen: () -> Void
    let onJump: (AgentSnapshot, AgentThread?) -> Void

    @State private var hoverTask: Task<Void, Never>?

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
            // Hover reveals the drop-down after a short dwell; moving to a
            // sibling row swaps the open one (accordion). Click still toggles.
            .onHover { hovering in
                hoverTask?.cancel()
                guard hovering, !isOpen else { return }
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(160))
                    if !Task.isCancelled { onHoverOpen() }
                }
            }

            if isOpen {
                dropDown
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isOpen ? 0.08 : 0)))
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
                    ThreadRow(thread: thread) { onJump(snapshot, thread) }
                }
            }
        }
        .padding(.leading, 26)
        .padding(.bottom, 6)
    }
}

struct ThreadRow: View {
    let thread: AgentThread
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                statusDot
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1)
                    if let subtitle = thread.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(relativeTimeFormatter.localizedString(for: thread.lastActivity, relativeTo: Date()))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Jump to this thread")
    }

    @ViewBuilder
    private var statusDot: some View {
        switch thread.status() {
        case .generating:
            SpinnerArc()
        case .waitingOnYou:
            PulsingDot(color: .orange)
        case .finishedUnread:
            // Blue owns "new result you haven't looked at".
            Circle().fill(HubbyGlass.unread).frame(width: 7, height: 7)
        case .active:
            Circle().fill(.white.opacity(0.5)).frame(width: 6, height: 6)
        case .idle:
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
        }
    }
}

/// A small rotating arc: this thread is generating right now.
struct SpinnerArc: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(.green, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 8, height: 8)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// A gently pulsing dot: this agent is blocked waiting on the human.
struct PulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(pulsing ? 1.4 : 0.8)
            .opacity(pulsing ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}
