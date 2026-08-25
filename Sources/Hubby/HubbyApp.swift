import AppKit
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var panelController: PanelController?
    private var store: ThreadStore?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = ThreadStore()
        let controller = PanelController()
        let root = RootView(store: store, panel: controller)

        let panel = FloatingPanel(content: root)
        controller.attach(panel: panel)
        panel.orderFrontRegardless()

        self.panel = panel
        self.panelController = controller
        self.store = store
        store.start()

        setUpStatusItem()
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "circle.hexagongrid.circle.fill", accessibilityDescription: "Hubby")

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Hubby", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh Threads", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Hubby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func showPanel() {
        panel?.orderFrontRegardless()
    }

    @objc private func refresh() {
        Task { @MainActor in store?.refresh() }
    }
}

/// Owns expand/collapse state and resizes the panel to match, anchored so the
/// orb's top-left corner stays put.
@MainActor
final class PanelController: ObservableObject {
    @Published private(set) var isExpanded = false
    private weak var panel: FloatingPanel?
    private var outsideClickMonitor: Any?

    func attach(panel: FloatingPanel) {
        self.panel = panel
    }

    func setExpanded(_ expanded: Bool) {
        guard let panel, expanded != isExpanded else { return }
        isExpanded = expanded
        updateOutsideClickMonitor()

        let pad = HubbyMetrics.panelPadding * 2
        let size = expanded
            ? CGSize(width: HubbyMetrics.hubSize.width + pad, height: HubbyMetrics.hubSize.height + pad)
            : CGSize(width: HubbyMetrics.orbDiameter + pad, height: HubbyMetrics.orbDiameter + pad)

        var frame = panel.frame
        // Keep the top-left corner fixed (AppKit origin is bottom-left).
        frame.origin.y += frame.height - size.height
        frame.size = size
        frame = clampToScreen(frame)
        panel.setFrame(frame, display: true, animate: true)
        panel.savePosition()
    }

    /// Clicking anywhere in another app collapses the hub. Global monitors
    /// only see events outside our own process, so clicks inside stay safe.
    private func updateOutsideClickMonitor() {
        if isExpanded {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.setExpanded(false) }
            }
        } else if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    private func clampToScreen(_ frame: NSRect) -> NSRect {
        guard let screen = panel?.screen ?? NSScreen.main else { return frame }
        var f = frame
        let visible = screen.visibleFrame
        f.origin.x = min(max(f.origin.x, visible.minX), max(visible.maxX - f.width, visible.minX))
        f.origin.y = min(max(f.origin.y, visible.minY), max(visible.maxY - f.height, visible.minY))
        return f
    }
}

/// Borderless, non-activating panel that floats above everything on every
/// Space. Dragging the background moves it; position persists across launches.
final class FloatingPanel: NSPanel {
    private static let positionKey = "HubbyPanelOrigin"
    private static let snapMargin: CGFloat = 24
    private static let snapInset: CGFloat = 8
    private var snapWorkItem: DispatchWorkItem?

    init<Content: View>(content: Content) {
        let pad = HubbyMetrics.panelPadding * 2
        let side = HubbyMetrics.orbDiameter + pad
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
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

        contentView = NSHostingView(rootView: content)
        restorePosition()

        // mouseUp is unreliable with a hosting view covering the panel, so
        // watch didMove instead: it fires throughout a drag, and a short
        // debounce means we snap + persist once the drag settles.
        NotificationCenter.default.addObserver(
            self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @objc private func didMove() {
        snapWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.snapToEdgeAndSave() }
        snapWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Pull the panel flush to any screen edge it was dropped near, then
    /// persist. Idempotent, so re-triggering via didMove converges.
    private func snapToEdgeAndSave() {
        guard let screen = screen ?? NSScreen.main else { savePosition(); return }
        let visible = screen.visibleFrame
        var f = frame
        if f.minX - visible.minX < Self.snapMargin { f.origin.x = visible.minX + Self.snapInset }
        if visible.maxX - f.maxX < Self.snapMargin { f.origin.x = visible.maxX - f.width - Self.snapInset }
        if f.minY - visible.minY < Self.snapMargin { f.origin.y = visible.minY + Self.snapInset }
        if visible.maxY - f.maxY < Self.snapMargin { f.origin.y = visible.maxY - f.height - Self.snapInset }
        if f.origin != frame.origin {
            setFrame(f, display: true, animate: true)
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
            // Default: upper-right corner, tucked below the menu bar.
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(
                x: visible.maxX - frame.width - 24,
                y: visible.maxY - frame.height - 24))
        }
    }
}
