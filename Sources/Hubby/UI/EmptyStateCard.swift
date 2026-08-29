import SwiftUI

/// First-run friendliness: when no adapter has any thread yet, the rows
/// area explains what Hubby is watching for instead of showing a wall of
/// empty app rows. Renders in place of the rows list; priorities and the
/// wordmark stay where they always are.
struct EmptyStateCard: View {
    /// Every enabled adapter's app info, in display order.
    let apps: [AgentAppInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No agent threads yet")
                .font(.system(.callout, design: .rounded).weight(.semibold))
            Text(
                "Hubby watches \(appList) for running sessions. " +
                "Start one and it appears here — shimmer while it's " +
                "generating, amber when it's waiting on you.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !WindowLocator.isTrusted {
                Button("Enable exact jumps…") {
                    WindowLocator.promptForTrust()
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(HubbyGlass.accent)
            }
        }
        .padding(14)
        .frame(width: HubbyMetrics.hubWidth - 32, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.03)))
        .padding(.vertical, 12)
    }

    private var appList: String {
        let names = apps.map(\.name)
        switch names.count {
        case 0: return "your agent apps"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}
