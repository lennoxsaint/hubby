import SwiftUI

/// Hosts the orb <-> hub morph. The panel never resizes; one spring animates
/// a single chrome shape between circle and rounded square while the content
/// cross-fades and the fan icons fly to their rows (matched geometry).
struct RootView: View {
    @ObservedObject var store: ThreadStore
    @ObservedObject var panel: PanelController

    @State private var jumpFailures = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            MorphSurface(expanded: panel.isExpanded) {
                if panel.isExpanded {
                    ExpandedHub(
                        snapshots: store.snapshots,
                        onJump: { snapshot, thread in
                            // A click means "seen" even when the jump fails.
                            if let thread {
                                store.markRead(appID: snapshot.id, thread: thread)
                            }
                            if store.source(for: snapshot.id)?.jump(to: thread) == true {
                                withAnimation(HubbyAnim.morph) { panel.setExpanded(false) }
                            } else {
                                // Missing app: shake instead of silently failing.
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) {
                                    jumpFailures += 1
                                }
                            }
                        },
                        onCollapse: {
                            withAnimation(HubbyAnim.morph) { panel.setExpanded(false) }
                        })
                    .transition(.opacity)
                } else {
                    CollapsedOrb(
                        snapshots: store.snapshots,
                        totalRunning: store.totalRunning,
                        totalNeedsYou: store.totalNeedsYou)
                    .transition(.spinFade)
                }
            }
            .modifier(Shake(shakes: CGFloat(jumpFailures)))
            // The tap lives OUTSIDE the chrome: gestures under a Material in
            // a movable-by-background window lose their mouseUp to AppKit's
            // window-drag session and never fire.
            .contentShape(Rectangle())
            .onTapGesture {
                if !panel.isExpanded {
                    withAnimation(HubbyAnim.morph) { panel.setExpanded(true) }
                }
            }
        }
        .padding(HubbyMetrics.panelPadding)
        .frame(
            width: HubbyMetrics.panelSize.width,
            height: HubbyMetrics.panelSize.height,
            alignment: .topLeading)
        .onPreferenceChange(HubHeightKey.self) { panel.setContentHeight($0) }
    }
}

/// The single morphing chrome: frame and corner radius interpolate between
/// orb and hub so the shape reads as one object throughout.
private struct MorphSurface<Content: View>: View {
    let expanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(
                width: expanded ? HubbyMetrics.hubWidth : HubbyMetrics.orbDiameter,
                height: expanded ? nil : HubbyMetrics.orbDiameter,
                alignment: .topLeading)
            .modifier(MorphChrome(
                radius: expanded ? HubbyMetrics.cornerRadius : HubbyMetrics.orbDiameter / 2))
    }
}

/// Animatable so the corner radius interpolates per-frame with the spring.
/// Material stays shape-scoped (`.background(_:in:)`) — a plain fill or a
/// post-hoc clip leaves a square NSVisualEffectView backing in a clear panel.
private struct MorphChrome: ViewModifier, Animatable {
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .clipShape(shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 5)
    }
}

/// Outgoing orb content spins away as the hub reveals — one gesture of the
/// same morph, not a separate animation.
private struct SpinFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active ? 50 : 0))
            .opacity(active ? 0 : 1)
    }
}

extension AnyTransition {
    static let spinFade = AnyTransition.modifier(
        active: SpinFade(active: true),
        identity: SpinFade(active: false))
}

/// Horizontal shake for failed jumps (missing target app).
private struct Shake: GeometryEffect {
    var travel: CGFloat = 6
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(shakes * .pi * 3), y: 0))
    }
}
