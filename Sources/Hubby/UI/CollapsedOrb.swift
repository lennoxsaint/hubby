import SwiftUI

/// The resting state's content: all six app icons arranged as a little
/// flower inside the blush glass, each carrying a small blue badge with its
/// unread-finished count. The icon nearest twelve o'clock — the one the hub
/// will open first — is drawn larger, on top, slightly overlapping its
/// neighbours, so the lead is unmistakable. The orb is also the fidget
/// surface: horizontal swipes cycle the fan, vertical/circular scrolling
/// spins the flower (settling commits the pin), pinch-in squeezes the icons
/// toward the centre, pinch-out blooms the hub open. When nothing needs the
/// user at all, the whole flower exhales — smaller, calmer, desaturated.
struct CollapsedOrb: View {
    let snapshots: [AgentSnapshot]
    /// Free flower rotation in degrees (PanelController's fidget spin).
    var spin: Double = 0
    /// Cumulative pinch magnification; negative gathers icons inward.
    var pinch: CGFloat = 0
    /// Nothing blocked, nothing unread — rest state.
    var allClear: Bool = false

    private static let restSize: CGFloat = 17
    private static let leadBoost: CGFloat = 10
    private static let ringRadius: CGFloat = 21

    var body: some View {
        // Pinch-in pulls the ring toward the centre (floor keeps icons
        // distinguishable); pinch-out pre-blooms slightly before the hub.
        let radius = Self.ringRadius * min(max(1 + pinch * 1.6, 0.22), 1.12)
        ZStack {
            ForEach(Array(snapshots.prefix(6).enumerated()), id: \.element.id) { index, snapshot in
                // First app at twelve o'clock, the rest clockwise; the
                // fidget spin rides on top of the layout angle.
                let angle = Double(index) * .pi / 3 - .pi / 2 + spin * .pi / 180
                // Lead-ness is continuous in angle so the enlargement
                // hands over smoothly while the flower spins.
                let lead = pow(max(0, (cos(angle + .pi / 2) + 1) / 2), 6)
                AppIconView(
                    info: snapshot.info,
                    size: Self.restSize + Self.leadBoost * lead,
                    dimmed: !snapshot.isRunning && snapshot.threads.isEmpty)
                .overlay(alignment: .topTrailing) {
                    UnreadBadge(count: snapshot.unreadCount)
                        .offset(x: 4, y: -4)
                }
                .offset(x: radius * cos(angle), y: radius * sin(angle))
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                .zIndex(lead)
            }
        }
        .scaleEffect(allClear ? 0.93 : 1)
        .saturation(allClear ? 0.8 : 1)
        .opacity(allClear ? 0.92 : 1)
        .animation(.easeInOut(duration: 0.5), value: allClear)
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
