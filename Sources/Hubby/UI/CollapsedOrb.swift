import SwiftUI

/// The resting state's content: a little 3D-ish deck of the most recently
/// active apps' icons, ringed by the machine-wide status arcs. Chrome
/// (glass circle, border, shadow) is drawn by the shared MorphSurface so
/// the shape morphs continuously.
struct CollapsedOrb: View {
    let snapshots: [AgentSnapshot]
    /// Machine-wide totals: running / needs-you / unread over all threads.
    let counts: RingCounts

    /// Fan shows the store's order (recency), frontmost = most recent.
    private var featured: [AgentSnapshot] {
        Array(snapshots.prefix(Self.fanCount))
    }

    private static let fanCount = 3

    var body: some View {
        ZStack {
            iconFan

            // The orb's rim is the badge: proportional arcs for running,
            // needs-you, and unread — legible however many threads exist.
            if !counts.isEmpty {
                SegmentedStatusRing(counts: counts, lineWidth: 2.5)
                    .padding(3)
            }

            if snapshots.count > Self.fanCount {
                Text("+\(snapshots.count - Self.fanCount)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(3)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .offset(x: HubbyMetrics.orbDiameter / 2 - 12,
                            y: HubbyMetrics.orbDiameter / 2 - 12)
            }

            // "Never leave an agent hanging": the one number that wants the
            // human — blocked agents + unread results, capped at 9+.
            if counts.attention > 0 {
                AttentionPill(count: counts.attention, urgent: counts.needsYou > 0)
                    .offset(x: HubbyMetrics.orbDiameter / 2 - 10,
                            y: -HubbyMetrics.orbDiameter / 2 + 10)
            }
        }
        .frame(width: HubbyMetrics.orbDiameter, height: HubbyMetrics.orbDiameter)
    }

    private var iconFan: some View {
        ZStack {
            ForEach(Array(featured.enumerated().reversed()), id: \.element.id) { index, snapshot in
                AppIconView(
                    info: snapshot.info,
                    size: 26,
                    dimmed: !snapshot.isRunning && snapshot.threads.isEmpty)
                .rotationEffect(.degrees(Double(index) * 9 - 9))
                .offset(x: CGFloat(index) * 8 - 8, y: CGFloat(index) * 2 - 2)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            }
        }
    }
}
