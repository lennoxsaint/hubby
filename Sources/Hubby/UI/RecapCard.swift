import SwiftUI

/// Reports each visible thread row's bounds so the hover recap card can
/// anchor itself to the row it describes.
struct RecapAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The cute little "what did this thread do" window: an ink-glass mini
/// panel floating by the hovered row. Display-only — it never takes hits,
/// so it can't perturb the panel's hit-test gating.
struct RecapCard: View {
    let thread: AgentThread

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusWord)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)
                Spacer(minLength: 12)
                Text(relativeTimeFormatter.localizedString(
                    for: thread.lastActivity, relativeTo: Date()))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Text(thread.title)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .lineLimit(1)
            if let recap = thread.recap {
                Text(recap)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let subtitle = thread.subtitle {
                // No recap from this source: at least say where it lives.
                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0x14141C).opacity(0.98)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HubbyGlass.hairline, lineWidth: 0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HubbyGlass.accent.opacity(0.3), lineWidth: 1)
                .blur(radius: 0.6))
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
        .allowsHitTesting(false)
    }

    private var statusWord: String {
        switch thread.status() {
        case .generating: "generating"
        case .waitingOnYou: "needs you"
        case .finishedUnread: "new result"
        case .active: "active"
        case .idle: "idle"
        }
    }

    private var statusColor: Color {
        switch thread.status() {
        case .generating: HubbyGlass.running
        case .waitingOnYou: HubbyGlass.needsYou
        case .finishedUnread: HubbyGlass.unread
        case .active: .white.opacity(0.6)
        case .idle: .secondary
        }
    }
}
