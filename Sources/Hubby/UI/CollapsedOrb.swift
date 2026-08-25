import SwiftUI

/// The resting state: a small circle showing the connected agent apps'
/// icons and a badge with the count of active threads.
struct CollapsedOrb: View {
    let snapshots: [AgentSnapshot]
    let totalActive: Int

    /// The four most interesting apps: running first, then by thread count.
    private var featured: [AgentSnapshot] {
        Array(snapshots
            .sorted {
                ($0.isRunning ? 1 : 0, $0.threads.count) > ($1.isRunning ? 1 : 0, $1.threads.count)
            }
            .prefix(4))
    }

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1)

            iconCluster
                .padding(10)

            if snapshots.count > 4 {
                Text("+\(snapshots.count - 4)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(3)
                    .background(Circle().fill(.black.opacity(0.45)))
                    .offset(x: HubbyMetrics.orbDiameter / 2 - 10,
                            y: HubbyMetrics.orbDiameter / 2 - 10)
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
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private var iconCluster: some View {
        let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(featured) { snapshot in
                ZStack {
                    Circle().fill(snapshot.info.tint.opacity(snapshot.isRunning ? 1 : 0.35))
                    Image(systemName: snapshot.info.symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 16, height: 16)
            }
        }
    }
}
