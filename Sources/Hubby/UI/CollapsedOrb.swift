import SwiftUI

/// The resting state's content: all six app icons arranged as a little
/// flower inside the blush glass, each carrying a small blue badge with its
/// unread-finished count. The swipe gesture rotates which app sits at
/// twelve o'clock (that app leads the hub). Chrome (glass circle, border,
/// shadow) is drawn by the shared MorphSurface so the shape morphs
/// continuously. No pills, chips, or rings — the badges are the signal.
struct CollapsedOrb: View {
    let snapshots: [AgentSnapshot]

    private static let iconSize: CGFloat = 19
    private static let ringRadius: CGFloat = 21

    var body: some View {
        ZStack {
            ForEach(Array(snapshots.prefix(6).enumerated()), id: \.element.id) { index, snapshot in
                // First app at twelve o'clock, the rest clockwise.
                let angle = Double(index) * .pi / 3 - .pi / 2
                AppIconView(
                    info: snapshot.info,
                    size: Self.iconSize,
                    dimmed: !snapshot.isRunning && snapshot.threads.isEmpty)
                .overlay(alignment: .topTrailing) {
                    UnreadBadge(count: snapshot.unreadCount)
                        .offset(x: 4, y: -4)
                }
                .offset(
                    x: Self.ringRadius * cos(angle),
                    y: Self.ringRadius * sin(angle))
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            }
        }
        .frame(width: HubbyMetrics.orbDiameter, height: HubbyMetrics.orbDiameter)
    }
}

/// A small blue circle with the count of finished-but-unread threads,
/// pinned to an app icon's top-right corner. Hidden at zero.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count > 9 ? "9+" : "\(count)")
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 11, minHeight: 11)
                .background(Circle().fill(HubbyGlass.unread))
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
                .transition(.scale.combined(with: .opacity))
        }
    }
}
