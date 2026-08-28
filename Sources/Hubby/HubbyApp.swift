import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@main
enum HubbyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar + floating panel only
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: FloatingPanel?
    private var panelController: PanelController?
    private var store: ThreadStore?
    private var statusItem: NSStatusItem?
    private var exactJumpsItem: NSMenuItem?
    private var hotkey: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ThreadStore()
        let controller = PanelController()

        let root = RootView(store: store, panel: controller)
        let panel = FloatingPanel(content: root, interactiveRect: {
            MainActor.assumeIsolated { controller.interactiveRect }
        })
        panel.visibleContentSize = {
            MainActor.assumeIsolated { controller.visibleContentSize }
        }
        panel.onUserDidMove = {
            MainActor.assumeIsolated { controller.userMovedPanel() }
        }
        controller.attach(panel: panel)
        panel.orderFrontRegardless()

        self.panel = panel
        self.panelController = controller
        self.store = store
        store.start()

        setUpStatusItem()

        // ⌃⌥H summons/dismisses the hub from anywhere.
        hotkey = HotkeyManager { [weak self] in
            guard let self, let controller = self.panelController else { return }
            self.panel?.orderFrontRegardless()
            withAnimation(HubbyAnim.morph) { controller.setExpanded(!controller.isExpanded) }
        }

        // Debug-only: drive the morph without synthetic clicks so visuals
        // can be captured deterministically. Harmless in normal runs.
        if ProcessInfo.processInfo.environment["HUBBY_AUTOTEST"] != nil {
            let controller = controller
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(HubbyAnim.morph) { controller.setExpanded(true) }
                try? await Task.sleep(for: .seconds(4))
                withAnimation(HubbyAnim.morph) { controller.setExpanded(false) }
            }
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "circle.hexagongrid.circle.fill", accessibilityDescription: "Hubby")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Hubby", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Threads", action: #selector(refresh), keyEquivalent: "r")
        // The way back in for users who dismissed the in-hub Accessibility
        // offer; hidden once the grant exists (see menuNeedsUpdate).
        let axItem = NSMenuItem(
            title: "Enable Exact Jumps…", action: #selector(enableExactJumps), keyEquivalent: "")
        menu.addItem(axItem)
        exactJumpsItem = axItem
        let loginItem = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hubby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        exactJumpsItem?.isHidden = WindowLocator.isTrusted
    }

    @objc private func enableExactJumps() {
        WindowLocator.promptForTrust()
    }

    @objc private func showPanel() {
        panel?.orderFrontRegardless()
    }

    @objc private func refresh() {
        Task { @MainActor in store?.refresh() }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Launch-at-login toggle failed: \(error)")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

/// Global hotkey via Carbon — no Accessibility permission needed.
final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    init?(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue().onPress()
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef) == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4855_4242), id: 1) // 'HUBB'
        guard RegisterEventHotKey(
            UInt32(kVK_ANSI_H), UInt32(controlKey | optionKey), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Owns expand/collapse state. The panel itself never resizes — it is always
/// big enough for the expanded hub, and the hosting view's hitTest passes
/// clicks through the unused clear area. The only window moves are instant,
/// invisible shifts to keep the hub on-screen when expanding near an edge.
@MainActor
final class PanelController: ObservableObject {
    @Published private(set) var isExpanded = false
    private weak var panel: FloatingPanel?
    private var outsideClickMonitor: Any?

    /// Last natural height reported by the hub content.
    private var hubContentHeight: CGFloat = 220
    /// Where the panel sat before an expand had to shift it to fit on-screen;
    /// collapse puts it back so the orb doesn't drift.
    private var preExpandOrigin: NSPoint?

    func attach(panel: FloatingPanel) {
        self.panel = panel
    }

    /// The rect the user can actually see/interact with, in hosting-view
    /// coordinates (top-left origin — the hosting view is flipped).
    var interactiveRect: CGRect {
        CGRect(
            origin: CGPoint(x: HubbyMetrics.panelPadding, y: HubbyMetrics.panelPadding),
            size: visibleContentSize)
    }

    var visibleContentSize: CGSize {
        isExpanded
            ? CGSize(
                width: HubbyMetrics.hubWidth,
                height: min(hubContentHeight, HubbyMetrics.maxHubHeight))
            : CGSize(width: HubbyMetrics.orbDiameter, height: HubbyMetrics.orbDiameter)
    }

    /// Call inside `withAnimation(HubbyAnim.morph)` — the state flip is the
    /// whole animation; no window resize happens.
    func setExpanded(_ expanded: Bool) {
        guard panel != nil, expanded != isExpanded else { return }
        if expanded { shiftToFitHub() }
        isExpanded = expanded
        updateOutsideClickMonitor()
        if !expanded { restorePreExpandOrigin() }
    }

    func setContentHeight(_ height: CGFloat) {
        if height > 0 { hubContentHeight = height }
    }

    /// A genuine user drag invalidates the remembered pre-expand origin.
    func userMovedPanel() {
        preExpandOrigin = nil
    }

    /// If expanding would push the hub off-screen (orb near the right or
    /// bottom edge), move the window instantly first. The panel chrome is
    /// invisible, so only the orb hops — immediately masked by the morph.
    private func shiftToFitHub() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let pad = HubbyMetrics.panelPadding
        let hubHeight = min(hubContentHeight, HubbyMetrics.maxHubHeight)
        var frame = panel.frame

        let contentLeft = frame.minX + pad
        let contentTop = frame.maxY - pad
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        let overRight = (contentLeft + HubbyMetrics.hubWidth) - (visible.maxX - 8)
        if overRight > 0 { dx = -overRight }
        let underBottom = (visible.minY + 8) - (contentTop - hubHeight)
        if underBottom > 0 { dy = underBottom }

        if dx != 0 || dy != 0 {
            preExpandOrigin = frame.origin
            frame.origin.x += dx
            frame.origin.y += dy
            panel.setFrameProgrammatically(frame)
        } else {
            preExpandOrigin = nil
        }
    }

    private func restorePreExpandOrigin() {
        if let origin = preExpandOrigin, let panel {
            var frame = panel.frame
            frame.origin = origin
            panel.setFrameProgrammatically(frame)
        }
        preExpandOrigin = nil
    }

    /// Clicking anywhere in another app collapses the hub. Global monitors
    /// only see events outside our own process, so clicks inside stay safe.
    private func updateOutsideClickMonitor() {
        if isExpanded {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    withAnimation(HubbyAnim.morph) { self?.setExpanded(false) }
                }
            }
        } else if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}

/// NSHostingView that only accepts events inside the visible content shape;
/// everything else falls through to whatever is beneath the clear panel.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: (() -> CGRect)?

    /// The panel is non-activating and usually not key; without first-mouse
    /// acceptance the initial click only orders the window and never reaches
    /// SwiftUI's gesture system.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let provider = interactiveRect else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        var rect = provider()
        if !isFlipped {
            rect.origin.y = bounds.height - rect.origin.y - rect.height
        }
        // Small slop so the hairline border still catches drags.
        guard rect.insetBy(dx: -4, dy: -4).contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// Borderless, non-activating, constant-size panel that floats above
/// everything on every Space. Dragging the content moves it; edge snapping
/// and persistence work against the *visible content* rect, not the panel.
final class FloatingPanel: NSPanel {
    // v2: origin semantics changed when the panel became constant-size.
    private static let positionKey = "HubbyPanelOrigin.v2"
    private static let snapMargin: CGFloat = 24
    private static let snapInset: CGFloat = 8
    private var snapWorkItem: DispatchWorkItem?
    private var isProgrammaticMove = false

    /// Supplied by the controller: the size of what's actually visible
    /// (orb or hub) so snapping targets the content edges.
    var visibleContentSize: (() -> CGSize)?
    var onUserDidMove: (() -> Void)?

    init<Content: View>(content: Content, interactiveRect: @escaping () -> CGRect) {
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
        let pad = HubbyMetrics.panelPadding
        let content = visibleContentSize?()
            ?? CGSize(width: HubbyMetrics.orbDiameter, height: HubbyMetrics.orbDiameter)
        var f = frame

        let left = f.minX + pad
        let right = left + content.width
        let top = f.maxY - pad
        let bottom = top - content.height

        if left - visible.minX < Self.snapMargin {
            f.origin.x = visible.minX + Self.snapInset - pad
        }
        if visible.maxX - right < Self.snapMargin {
            f.origin.x = visible.maxX - Self.snapInset - content.width - pad
        }
        if bottom - visible.minY < Self.snapMargin {
            f.origin.y = visible.minY + Self.snapInset + content.height + pad - f.height
        }
        if visible.maxY - top < Self.snapMargin {
            f.origin.y = visible.maxY - Self.snapInset + pad - f.height
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
        } else if let screen = NSScreen.main {
            // Default: orb tucked into the upper-right corner.
            let visible = screen.visibleFrame
            let pad = HubbyMetrics.panelPadding
            setFrameOrigin(NSPoint(
                x: visible.maxX - Self.snapInset - HubbyMetrics.orbDiameter - pad,
                y: visible.maxY - Self.snapInset + pad - frame.height))
        }
    }
}
