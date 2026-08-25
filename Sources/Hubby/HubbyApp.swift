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

    func attach(panel: FloatingPanel) {
        self.panel = panel
    }

    func setExpanded(_ expanded: Bool) {
        guard let panel, expanded != isExpanded else { return }
        isExpanded = expanded

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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
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
