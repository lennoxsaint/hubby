import AppKit
import SwiftUI

/// NSHostingView that only accepts events inside the visible content shape;
/// everything else falls through to whatever is beneath the clear panel.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: (() -> CGRect)?
    /// A second interactive region: the hover card floating in a gutter
    /// OUTSIDE the hub rect. Nil when no card is showing.
    var auxiliaryRect: (() -> CGRect?)?

    /// The panel is non-activating and usually not key; without first-mouse
    /// acceptance the initial click only orders the window and never reaches
    /// SwiftUI's gesture system.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    /// The fan cycler gets first refusal on scrolls (collapsed orb only);
    /// everything it declines flows on to SwiftUI — the hub's ScrollView
    /// depends on that.
    override func scrollWheel(with event: NSEvent) {
        if (window as? FloatingPanel)?.onFanScroll?(event) == true { return }
        super.scrollWheel(with: event)
    }

    /// Trackpad pinch feeds the orb fidget (squeeze / bloom-open). Also
    /// forwarded to super so SwiftUI gestures aren't starved if any appear.
    override func magnify(with event: NSEvent) {
        (window as? FloatingPanel)?.onMagnify?(event)
        super.magnify(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let provider = interactiveRect else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        // Small slop so the hairline border still catches drags.
        if flipped(provider()).insetBy(dx: -4, dy: -4).contains(local) {
            return super.hitTest(point)
        }
        if let aux = auxiliaryRect?() ,
           flipped(aux).insetBy(dx: -4, dy: -4).contains(local) {
            return super.hitTest(point)
        }
        return nil
    }

    private func flipped(_ rect: CGRect) -> CGRect {
        guard !isFlipped else { return rect }
        var r = rect
        r.origin.y = bounds.height - r.origin.y - r.height
        return r
    }
}

/// Borderless, non-activating, constant-size panel that floats above
/// everything on every Space. Dragging the content moves it; edge snapping
/// and persistence work against the *visible content* rect, not the panel.
final class FloatingPanel: NSPanel {
    // v2: origin semantics changed when the panel became constant-size.
    // v3: the panel grew a card gutter either side; the content shifted
    //     right by one gutter inside the frame, so old origins migrate.
    private static let positionKey = "HubbyPanelOrigin.v3"
    private static let legacyPositionKey = "HubbyPanelOrigin.v2"
    private static let snapMargin: CGFloat = 24
    private static let snapInset: CGFloat = 8
    private var snapWorkItem: DispatchWorkItem?
    private var isProgrammaticMove = false

    /// Supplied by the controller: the size of what's actually visible
    /// (orb or hub) so snapping targets the content edges.
    var visibleContentSize: (() -> CGSize)?
    var onUserDidMove: (() -> Void)?
    /// Fan-cycle scroll handler; returns true when the event was consumed.
    var onFanScroll: ((NSEvent) -> Bool)?
    /// Trackpad pinch handler (collapsed-orb fidget).
    var onMagnify: ((NSEvent) -> Void)?

    init<Content: View>(
        content: Content,
        interactiveRect: @escaping () -> CGRect,
        auxiliaryRect: @escaping () -> CGRect? = { nil }
    ) {
        let size = HubbyMetrics.panelSize
        // No .fullSizeContentView: on macOS 14+ it drags in the scene
        // background / safe-area path that paints a gray square behind us.
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // SwiftUI draws its own shadows
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true // hover accordion needs mouse-moved

        let hosting = PassthroughHostingView(rootView: content)
        hosting.interactiveRect = interactiveRect
        hosting.auxiliaryRect = auxiliaryRect
        hosting.safeAreaRegions = [] // no scene-background square on 14+
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = hosting
        restorePosition()

        // mouseUp is unreliable with a hosting view covering the panel, so
        // watch didMove instead: it fires throughout a drag, and a short
        // debounce means we snap + persist once the drag settles.
        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Window moves Hubby makes itself (fit-on-screen shifts, snaps) must not
    /// re-trigger the drag-settle pipeline.
    func setFrameProgrammatically(_ frame: NSRect, animate: Bool = false) {
        isProgrammaticMove = true
        setFrame(frame, display: true, animate: animate)
        isProgrammaticMove = false
    }

    @objc private func didMove() {
        guard !isProgrammaticMove else { return }
        onUserDidMove?()
        snapWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.snapToEdgeAndSave() }
        snapWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Pull the visible content flush to any screen edge it was dropped near,
    /// then persist. Idempotent, so re-triggering via didMove converges.
    private func snapToEdgeAndSave() {
        guard let screen = screen ?? NSScreen.main else { savePosition(); return }
        let visible = screen.visibleFrame
        let padX = HubbyMetrics.contentInsetX
        let padY = HubbyMetrics.panelPadding
        let content = visibleContentSize?()
            ?? CGSize(width: HubbyMetrics.orbDiameter, height: HubbyMetrics.orbDiameter)
        var f = frame

        let left = f.minX + padX
        let right = left + content.width
        let top = f.maxY - padY
        let bottom = top - content.height

        if left - visible.minX < Self.snapMargin {
            f.origin.x = visible.minX + Self.snapInset - padX
        }
        if visible.maxX - right < Self.snapMargin {
            f.origin.x = visible.maxX - Self.snapInset - content.width - padX
        }
        if bottom - visible.minY < Self.snapMargin {
            f.origin.y = visible.minY + Self.snapInset + content.height + padY - f.height
        }
        if visible.maxY - top < Self.snapMargin {
            f.origin.y = visible.maxY - Self.snapInset + padY - f.height
        }
        if f.origin != frame.origin {
            setFrameProgrammatically(f, animate: true)
        }
        savePosition()
    }

    func savePosition() {
        UserDefaults.standard.set(NSStringFromPoint(frame.origin), forKey: Self.positionKey)
    }

    private func restorePosition() {
        if let saved = UserDefaults.standard.string(forKey: Self.positionKey) {
            setFrameOrigin(NSPointFromString(saved))
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacyPositionKey) {
            // Keep the visible content where it was: the frame gained one
            // gutter of leading margin, so the origin slides left by it.
            var origin = NSPointFromString(legacy)
            origin.x -= HubbyMetrics.cardGutter
            setFrameOrigin(origin)
            savePosition()
            UserDefaults.standard.removeObject(forKey: Self.legacyPositionKey)
        } else if let screen = NSScreen.main {
            // Default: orb tucked into the upper-right corner.
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(
                x: visible.maxX - Self.snapInset - HubbyMetrics.orbDiameter
                    - HubbyMetrics.contentInsetX,
                y: visible.maxY - Self.snapInset + HubbyMetrics.panelPadding - frame.height))
        }
    }
}
