import SwiftUI

/// The resting state's content: a little 3D-ish deck of the most recently
/// active apps' icons plus badges. Chrome (material circle, border, shadow)
/// is drawn by the shared MorphSurface so the shape morphs continuously.
struct CollapsedOrb: View {
    let snapshots: [AgentSnapshot]
    let totalRunning: Int
    let totalNeedsYou: Int

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

            if totalRunning > 0 {
                Text("\(totalRunning)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.green))
                    .offset(x: HubbyMetrics.orbDiameter / 2 - 10,
                            y: -HubbyMetrics.orbDiameter / 2 + 10)
            }

            // "Never leave an agent hanging": amber badge when any agent is
            // blocked waiting on the human.
            if totalNeedsYou > 0 {
                Text("\(totalNeedsYou)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange))
                    .offset(x: -HubbyMetrics.orbDiameter / 2 + 10,
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
