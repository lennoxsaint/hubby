import SwiftUI

/// Hosts the orb ↔ hub morph. The panel resize itself is driven by
/// `PanelController`; this view animates the content between the two shapes.
struct RootView: View {
    @ObservedObject var store: ThreadStore
    @ObservedObject var panel: PanelController

    var body: some View {
        ZStack(alignment: .topLeading) {
            if panel.isExpanded {
                ExpandedHub(
                    snapshots: store.snapshots,
                    onJump: { snapshot, thread in
                        store.source(for: snapshot.id)?.jump(to: thread)
                    },
                    onCollapse: { panel.setExpanded(false) })
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.2, anchor: .topLeading).combined(with: .opacity),
                    removal: .scale(scale: 0.2, anchor: .topLeading).combined(with: .opacity)))
            } else {
                CollapsedOrb(snapshots: store.snapshots, totalActive: store.totalActive)
                    .onTapGesture { panel.setExpanded(true) }
                    .transition(.scale(scale: 1.6, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .padding(HubbyMetrics.panelPadding)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: panel.isExpanded)
    }
}
