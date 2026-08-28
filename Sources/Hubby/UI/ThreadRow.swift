import SwiftUI

/// One thread inside an app's drop-down: status dot, title, project, time.
/// Clicking jumps; a 500ms hover dwell floats the recap card (the row
/// publishes its bounds through RecapAnchorKey for anchoring).
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
        // No .help here: the tooltip's own tracking swallowed the row's
        // hover events in this borderless panel, killing the recap dwell.
        // Rows always publish their bounds; the hub only reads the hovered
        // one's. 500ms dwell — long enough to mean "tell me more".
        .anchorPreference(key: RecapAnchorKey.self, value: .bounds) {
            [thread.id: $0]
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch thread.status() {
        case .generating:
            SpinnerArc()
        case .waitingOnYou:
            PulsingDot(color: HubbyGlass.needsYou)
        case .finishedUnread:
            // Blue owns "new result you haven't looked at".
            Circle().fill(HubbyGlass.unread).frame(width: 7, height: 7)
        case .active:
            Circle().fill(.black.opacity(0.4)).frame(width: 6, height: 6)
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
            .stroke(HubbyGlass.running, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
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
