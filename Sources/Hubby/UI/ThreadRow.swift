import SwiftUI

/// One thread inside an app's drop-down: status dot, title, project, time.
/// Clicking jumps; a short hover dwell floats the recap card beside the hub
/// (the row publishes its bounds through RecapAnchorKey for anchoring).
struct ThreadRow: View {
    let thread: AgentThread
    /// The hub's ticking clock — times and statuses re-evaluate live
    /// against it instead of freezing at the last snapshot render.
    var now: Date = Date()
    /// Distinguishes anchor namespaces when the same thread renders twice.
    var anchorPrefix: String = ""
    /// Poller-derived hover (the pin glyph fades in on it).
    var hovered: Bool = false
    let onTap: () -> Void
    var onPin: (() -> Void)? = nil
    /// Approve/Choose pill click; the hub decides what it means by kind.
    var onPillTap: (() -> Void)? = nil

    /// The shimmer sweep's cell domain: the status dot at cell 0, the
    /// title from cell 2 — one continuous band, like Codex's "• Working".
    private var rowCells: Double { Double(thread.title.count) + 2 }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                statusDot
                // No subtitle line: project paths were most of the row
                // noise, and the hover recap card carries full context.
                if thread.status(now: now) == .generating {
                    ShimmerText(
                        text: thread.title,
                        font: .system(.callout, design: .rounded),
                        cellOffset: 2,
                        rowCells: rowCells)
                } else {
                    Text(thread.title)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1)
                }
                Spacer()
                if let prompt = thread.pendingPrompt, let onPillTap {
                    PromptPill(prompt: prompt, onTap: onPillTap)
                }
                Text(relativeTimeFormatter.localizedString(for: thread.lastActivity, relativeTo: now))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .opacity(0.7)
                if let onPin, hovered || thread.isPinned {
                    Button(action: onPin) {
                        Image(systemName: thread.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                thread.isPinned
                                    ? HubbyGlass.accent : Color.black.opacity(0.35))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            // Poller-driven hover has no withAnimation context; without this
            // the pin glyph pops/flickers at the 80ms tick rate.
            .animation(.easeOut(duration: 0.1), value: hovered)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // No .help here: the tooltip's own tracking swallowed the row's
        // hover events in this borderless panel, killing the recap dwell.
        // Rows always publish their bounds; the hub only reads the hovered
        // one's.
        .anchorPreference(key: RecapAnchorKey.self, value: .bounds) {
            [anchorPrefix + thread.id: $0]
        }
    }

    /// A dot appears only when it matters: shimmer for generating, amber
    /// for blocked. Every other state gets a clean left edge — the spacer
    /// keeps titles aligned with the rows that do carry a dot.
    @ViewBuilder
    private var statusDot: some View {
        switch thread.status(now: now) {
        case .generating:
            ShimmerDot(rowCells: rowCells)
        case .waitingOnYou:
            PulsingDot(color: HubbyGlass.needsYou)
        case .finishedUnread, .active, .idle:
            Color.clear.frame(width: 7, height: 7)
        }
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
