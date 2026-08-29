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
    /// The centre octopus's total angle: live spin plus the whole turns
    /// banked by fan cycles/settles, so it turns with BOTH gestures.
    var octopusAngle: Double = 0
    /// Cumulative pinch magnification; negative gathers icons inward.
    var pinch: CGFloat = 0
    /// Nothing blocked, nothing unread — rest state.
    var allClear: Bool = false

    var body: some View {
        // Geometry lives in OrbLayout — shared with the tap hit-testing so
        // a click lands on exactly the icon it visually hits.
        ZStack {
            // The mascot at the flower's heart, spinning with it. Same
            // vector rendition as the wordmark so the expand reads as one
            // octopus travelling from orb centre to hub bottom.
            OctopusView(size: 22)
                .rotationEffect(.degrees(octopusAngle))
            ForEach(Array(snapshots.prefix(6).enumerated()), id: \.element.id) { index, snapshot in
                let angle = OrbLayout.angle(index: index, spin: spin)
                let lead = OrbLayout.lead(angle: angle)
                let center = OrbLayout.center(index: index, spin: spin, pinch: pinch)
                let mid = HubbyMetrics.orbDiameter / 2
                AppIconView(
                    info: snapshot.info,
                    size: OrbLayout.iconSize(index: index, spin: spin),
                    dimmed: !snapshot.isRunning && snapshot.threads.isEmpty)
                .overlay(alignment: .topTrailing) {
                    UnreadBadge(count: snapshot.unreadCount)
                        .offset(x: 4, y: -4)
                }
                .offset(x: center.x - mid, y: center.y - mid)
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
