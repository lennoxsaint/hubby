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

/// The hover card answers exactly one question in plain words: what just
/// happened, and is it finished or does it need you? A verdict line, then
/// at most one sentence of the thread's last message — plus tiny actions
/// (copy the result, mark read, nudge) when the hub provides them. The
/// hub's overlay keeps the card alive while the cursor is inside it.
struct RecapCard: View {
    let thread: AgentThread
    var onCopy: (() -> Void)? = nil
    var onMarkRead: (() -> Void)? = nil
    var onNudge: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(verdict.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(verdict.color)
                Text(verdict.words)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(verdict.color)
                Spacer(minLength: 12)
                Text(relativeTimeFormatter.localizedString(
                    for: thread.lastActivity, relativeTo: Date()))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            Text(thread.title)
                .font(.system(size: 11, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let sentence = thread.recap.flatMap({ RecapText.excerpt($0) }) {
                Text(sentence)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if onCopy != nil || onMarkRead != nil || onNudge != nil {
                HStack(spacing: 10) {
                    if let onCopy, thread.recap != nil {
                        control("doc.on.doc", "Copy", action: onCopy)
                    }
                    if let onMarkRead, thread.isFinishedUnread {
                        control("checkmark.circle", "Mark read", action: onMarkRead)
                    }
                    if let onNudge {
                        control("hand.tap", "Nudge", action: onNudge)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0xFCF3F5).opacity(0.98)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HubbyGlass.hairline, lineWidth: 0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HubbyGlass.accent.opacity(0.35), lineWidth: 1)
                .blur(radius: 0.6))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private func control(
        _ symbol: String, _ label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 9, weight: .medium))
                Text(label).font(.system(size: 9.5, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var verdict: (symbol: String, words: String, color: Color) {
        switch thread.status() {
        case .generating:
            ("●", "Still working…", HubbyGlass.running)
        case .waitingOnYou:
            ("⚠", "Waiting on you", HubbyGlass.needsYou)
        case .finishedUnread:
            ("✓", "Finished — nothing needed", HubbyGlass.unread)
        case .active, .idle:
            ("✓", "Finished", Color.black.opacity(0.55))
        }
    }
}

