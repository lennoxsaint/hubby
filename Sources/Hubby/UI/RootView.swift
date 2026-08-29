import SwiftUI

/// Hosts the orb <-> hub morph. The panel never resizes; one spring animates
/// a single chrome shape between circle and rounded square while the content
/// cross-fades and the fan icons fly to their rows (matched geometry).
struct RootView: View {
    @ObservedObject var store: ThreadStore
    @ObservedObject var panel: PanelController

    @State private var jumpFailures = 0
    @State private var axPrompt = false
    /// The user's top-three list, shown above the accordions.
    @StateObject private var priorities = PriorityStore()
    /// The hovered thread's card id. Owned here because the card renders in
    /// CardOverlay OUTSIDE the morph chrome (its clip covers the gutters);
    /// the hub's hover poller drives it through a binding.
    @State private var recapID: String?

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
                        priorities: priorities,
                        // The hub always arrives with the top app's threads
                        // already open — a swipe/spin/icon-tap pick decides
                        // which app that is; otherwise the most active one.
                        initialOpenApp: panel.pinnedTopID ?? orderedSnapshots.first?.id,
                        cardSide: panel.cardSide,
                        recapID: $recapID,
                        onJump: handleJump,
                        onCollapse: {
                            withAnimation(HubbyAnim.morph) { panel.setExpanded(false) }
                        },
                        onAnswer: handleAnswer,
                        onTogglePin: { snapshot, thread in
                            store.togglePin(appID: snapshot.id, thread: thread)
                        },
                        onDismiss: { snapshot, thread in
                            store.dismiss(appID: snapshot.id, thread: thread)
                        },
                        onCardRect: { panel.setCardRect($0) })
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
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                } else {
                    CollapsedOrb(
                        snapshots: orderedSnapshots,
                        spin: panel.orbSpin,
                        octopusAngle: panel.orbSpin + Double(panel.fanTurns) * 60,
                        pinch: panel.orbPinch,
                        allClear: orderedSnapshots.allSatisfy {
                            $0.needsYouCount == 0 && $0.unreadCount == 0
                        })
                        .transition(.spinFade)
                }
            }
            .modifier(Shake(shakes: CGFloat(jumpFailures)))
            // Bloom: a soft scale overshoot rides on top of the morph
            // spring. Applied OUTSIDE the chrome (like Shake) so the
            // momentary 3% growth never displaces hit-testing inside it.
            .keyframeAnimator(
                initialValue: 1.0, trigger: panel.isExpanded
            ) { view, scale in
                view.scaleEffect(scale, anchor: .topLeading)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.03, duration: 0.2)
                    SpringKeyframe(1.0, duration: 0.3)
                }
            }
            // The tap lives OUTSIDE the chrome: gestures under a Material in
            // a movable-by-background window lose their mouseUp to AppKit's
            // window-drag session and never fire. Spatial so a tap landing
            // on a flower icon makes THAT app lead the hub it opens.
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                guard !panel.isExpanded else { return }
                if let index = OrbLayout.hitIndex(
                    point: value.location, count: orderedSnapshots.count,
                    spin: panel.orbSpin, pinch: panel.orbPinch) {
                    panel.leadApp(orderedSnapshots[index].id)
                }
                withAnimation(HubbyAnim.morph) { panel.setExpanded(true) }
            })
            // The hover card floats in a side gutter BEYOND the hub's edge,
            // so it must render outside MorphChrome (whose clipShape would
            // swallow it). The row anchors bubble up here as preferences.
            .overlayPreferenceValue(RecapAnchorKey.self) { anchors in
                if panel.isExpanded {
                    CardOverlay(
                        anchors: anchors,
                        snapshots: orderedSnapshots,
                        side: panel.cardSide,
                        recapID: $recapID,
                        onAnswer: handleAnswer,
                        onMarkRead: { snapshot, thread in
                            store.markRead(appID: snapshot.id, thread: thread)
                        },
                        onNudge: handleNudge)
                }
            }
        }
        .onChange(of: panel.isExpanded) {
            recapID = nil
            // The hub opens on fresh data, not the last tick's (which can
            // be a full fallback interval old).
            if panel.isExpanded { store.refresh() }
        }
        .padding(.horizontal, HubbyMetrics.contentInsetX)
        .padding(.vertical, HubbyMetrics.panelPadding)
        .frame(
            width: HubbyMetrics.panelSize.width,
            height: HubbyMetrics.panelSize.height,
            alignment: .topLeading)
        // The blush glass is one committed look: resolve every semantic color
        // for light so dark-mode desktops don't get white-on-white text.
        .environment(\.colorScheme, .light)
        .onPreferenceChange(HubHeightKey.self) { panel.setContentHeight($0) }
    }

    /// Approve/option click: run the guarded actuation; on success the
    /// refresh clears the blocked tier, on any failed guard fall back to a plain
    /// jump so the user can answer by hand. Nothing is typed on fallback.
    private func handleAnswer(snapshot: AgentSnapshot, thread: AgentThread, optionIndex: Int?) {
        guard let source = store.source(for: snapshot.id) as? ClaudeCodeSource,
              let prompt = thread.pendingPrompt else {
            handleJump(snapshot: snapshot, thread: thread)
            return
        }
        Task { @MainActor in
            switch await source.answer(thread, prompt: prompt, optionIndex: optionIndex) {
            case .answered:
                store.refresh()
            case .fellBack:
                handleJump(snapshot: snapshot, thread: thread)
            }
        }
    }

    /// Nudge an idle Claude Code session ("continue" + Return, guarded).
    private func handleNudge(snapshot: AgentSnapshot, thread: AgentThread) {
        guard let source = store.source(for: snapshot.id) as? ClaudeCodeSource else { return }
        Task { @MainActor in
            switch await source.nudge(thread) {
            case .answered:
                store.refresh()
            case .fellBack:
                handleJump(snapshot: snapshot, thread: thread)
            }
        }
    }

    private func handleJump(snapshot: AgentSnapshot, thread: AgentThread?) {
        // A click means "seen" even when the jump fails.
        if let thread {
            store.markRead(appID: snapshot.id, thread: thread)
        }
        let resolution = store.source(for: snapshot.id)?.jump(to: thread) ?? .failed
        if ProcessInfo.processInfo.environment["HUBBY_DEBUG"] != nil {
            FileHandle.standardError.write(Data(
                "jump app=\(snapshot.id) thread=\(thread?.title ?? "-") resolution=\(resolution) trusted=\(WindowLocator.isTrusted) shouldOffer=\(AXOnboarding.shouldOffer)\n".utf8))
        }
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
            // Grab anywhere along the outer edge to move the board (the
            // interior stays interactive; the ring hit-tests only its band).
            .overlay { if expanded { WindowDragRing() } }
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
            // One flat blush sheet: no sheen, no rim glow — just a whisper
            // of a hairline so the glass melts into the desktop instead of
            // reading as an outlined shape.
            .overlay(
                shape.strokeBorder(Color.black.opacity(0.045), lineWidth: 0.5)
                    .blur(radius: 0.4)
                    .allowsHitTesting(false))
            // Exactly ONE shadow, envelope (radius + offset) under
            // `panelPadding`. Two stacked .shadow modifiers rendered a
            // shadow OF the first shadow's soft-alpha rectangle — a faint
            // square halo on light desktops (bisected on-screen 29 Aug).
            // Exceeding the padding hard-clips into a square the same way.
            .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
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
