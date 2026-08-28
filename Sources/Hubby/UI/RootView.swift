import SwiftUI

/// Hosts the orb <-> hub morph. The panel never resizes; one spring animates
/// a single chrome shape between circle and rounded square while the content
/// cross-fades and the fan icons fly to their rows (matched geometry).
struct RootView: View {
    @ObservedObject var store: ThreadStore
    @ObservedObject var panel: PanelController

    @State private var jumpFailures = 0
    @State private var axPrompt = false

    /// The store's smart order, rotated by any fan-swipe pin so the chosen
    /// app leads both the orb stack and the hub rows.
    private var orderedSnapshots: [AgentSnapshot] {
        FanRotation.rotated(store.snapshots, top: panel.pinnedTopID)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MorphSurface(expanded: panel.isExpanded) {
                if panel.isExpanded {
                    ExpandedHub(
                        snapshots: orderedSnapshots,
                        // A deliberate swipe means "show me this app":
                        // arrive with its threads already open.
                        initialOpenApp: panel.pinnedTopID,
                        onJump: handleJump,
                        onCollapse: {
                            withAnimation(HubbyAnim.morph) { panel.setExpanded(false) }
                        })
                    .overlay(alignment: .bottom) {
                        if axPrompt {
                            AXOnboardingCard(
                                onOpenSettings: {
                                    WindowLocator.promptForTrust()
                                    withAnimation(.spring(duration: 0.25)) { axPrompt = false }
                                },
                                onDismiss: {
                                    AXOnboarding.decline()
                                    withAnimation(.spring(duration: 0.25)) { axPrompt = false }
                                })
                            .padding(10)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }
                    }
                    .transition(.opacity)
                } else {
                    CollapsedOrb(
                        snapshots: orderedSnapshots,
                        counts: RingCounts(
                            running: store.totalRunning,
                            needsYou: store.totalNeedsYou,
                            unread: store.totalUnread,
                            total: store.totalThreads))
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
        // The ink glass is one committed look: resolve every semantic color
        // for dark so light-mode desktops don't get gray-on-black text.
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(HubHeightKey.self) { panel.setContentHeight($0) }
    }

    private func handleJump(snapshot: AgentSnapshot, thread: AgentThread?) {
        // A click means "seen" even when the jump fails.
        if let thread {
            store.markRead(appID: snapshot.id, thread: thread)
        }
        let resolution = store.source(for: snapshot.id)?.jump(to: thread) ?? .failed
        switch resolution {
        case .failed:
            // Missing app: shake instead of silently failing.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.4)) {
                jumpFailures += 1
            }
        case .needsAccessibility where AXOnboarding.shouldOffer:
            // The app was activated behind us; hold the hub open for the
            // one-time Accessibility pitch instead of collapsing over it.
            AXOnboarding.markOffered()
            withAnimation(.spring(duration: 0.3)) { axPrompt = true }
        default:
            withAnimation(HubbyAnim.morph) { panel.setExpanded(false) }
        }
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
/// The ink glass replaced the system Material, but every fill and stroke
/// stays scoped to the morphing shape — a plain fill or a post-hoc clip
/// painted a square backing in this clear panel, and the discipline holds.
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
            .background(shape.fill(HubbyGlass.base))
            .background(shape.fill(HubbyGlass.floor))
            .overlay(shape.fill(HubbyGlass.sheen).allowsHitTesting(false))
            .overlay(shape.strokeBorder(HubbyGlass.hairline, lineWidth: 0.5))
            .overlay(
                shape.strokeBorder(HubbyGlass.rim, lineWidth: 1)
                    .blur(radius: 0.6)
                    .allowsHitTesting(false))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
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
