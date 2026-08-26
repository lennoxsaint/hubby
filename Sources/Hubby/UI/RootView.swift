import SwiftUI

/// Hosts the orb ↔ hub morph. The panel resize itself is driven by
/// `PanelController`; this view animates the content between the two shapes,
/// with a playful spin as the orb blooms into the hub.
struct RootView: View {
    @ObservedObject var store: ThreadStore
    @ObservedObject var panel: PanelController

    @State private var spin = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if panel.isExpanded {
                ExpandedHub(
                    snapshots: store.snapshots,
                    onJump: { snapshot, thread in
                        store.source(for: snapshot.id)?.jump(to: thread)
                    },
                    onCollapse: { panel.setExpanded(false) })
                .transition(.spinMorph)
            } else {
                CollapsedOrb(snapshots: store.snapshots, totalActive: store.totalActive)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                            spin.toggle()
                        }
                        panel.setExpanded(true)
                    }
                    .transition(.scale(scale: 1.6, anchor: .topLeading).combined(with: .opacity))
            }
        }
        .padding(HubbyMetrics.panelPadding)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: panel.isExpanded)
        .onPreferenceChange(HubHeightKey.self) { height in
            panel.setContentHeight(height)
        }
    }
}

/// Scale + slight counter-rotation + fade: the hub appears to spin out of
/// the orb rather than just popping.
private struct SpinMorph: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? 0.2 : 1, anchor: .topLeading)
            .rotationEffect(.degrees(active ? -14 : 0), anchor: .topLeading)
            .opacity(active ? 0 : 1)
    }
}

extension AnyTransition {
    static let spinMorph = AnyTransition.modifier(
        active: SpinMorph(active: true),
        identity: SpinMorph(active: false))
}
