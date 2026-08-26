import SwiftUI

/// The resting state: a small circle showing the connected agent apps'
/// icons and a badge with the count of active threads.
struct CollapsedOrb: View {
    let snapshots: [AgentSnapshot]
    let totalActive: Int

    /// Fan shows the store's order (recency), frontmost = most recent.
    private var featured: [AgentSnapshot] {
        Array(snapshots.prefix(Self.fanCount))
    }

    private static let fanCount = 3

    var body: some View {
        ZStack {
            iconFan

            if snapshots.count > Self.fanCount {
                Text("+\(snapshots.count - Self.fanCount)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(3)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .offset(x: HubbyMetrics.orbDiameter / 2 - 12,
                            y: HubbyMetrics.orbDiameter / 2 - 12)
            }

            if totalActive > 0 {
                Text("\(totalActive)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.green))
                    .offset(x: HubbyMetrics.orbDiameter / 2 - 10,
                            y: -HubbyMetrics.orbDiameter / 2 + 10)
            }
        }
        .frame(width: HubbyMetrics.orbDiameter, height: HubbyMetrics.orbDiameter)
        // Shape-scoped material: `fill(.ultraThinMaterial)` leaves a square
        // NSVisualEffectView backing behind the circle in a clear panel.
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    /// A little 3D-ish deck of the most recently active apps' real icons.
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
