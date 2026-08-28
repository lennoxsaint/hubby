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
        panel.onFanScroll = { event in
            MainActor.assumeIsolated {
                controller.handleFanScroll(event, order: store.snapshots.map(\.id))
            }
        }
        panel.onMagnify = { event in
            MainActor.assumeIsolated { controller.handleMagnify(event) }
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

    @MainActor
    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let glyph = OctopusGlyph.menuBarImage()
        glyph.accessibilityDescription = "Hubby"
        item.button?.image = glyph

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
    /// Which app a fan swipe pinned on top; nil = the store's smart order.
    /// Ephemeral: cleared on collapse and after 30s of collapsed idling.
    @Published private(set) var pinnedTopID: String?
    /// Free rotation of the collapsed flower, in degrees — the fidget spin.
    /// Settles to a multiple of 60° and commits the nearest icon as pin.
    @Published private(set) var orbSpin: Double = 0
    /// Cumulative pinch magnification over the orb (negative = pinch-in,
    /// gathers the icons; a big pinch-out blooms the hub open).
    @Published private(set) var orbPinch: CGFloat = 0
    private weak var panel: FloatingPanel?
    private var outsideClickMonitor: Any?
    private var pinResetTask: Task<Void, Never>?
    private var spinSettleTask: Task<Void, Never>?
    private var scrollAccumulator: CGFloat = 0

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
        if expanded {
            shiftToFitHub()
            // The pin survives into the hub (it decides which app is first);
            // only the idle countdown stops.
            pinResetTask?.cancel()
        }
        isExpanded = expanded
        updateOutsideClickMonitor()
        if !expanded {
            restorePreExpandOrigin()
            // Collapse hands the stack back to the smart order.
            pinnedTopID = nil
        }
    }

    /// One fan swipe step over the collapsed orb: the top icon slides under
    /// the stack, the next rises. Consumes the event when it applies.
    /// `order` is the store's current (unrotated) app order.
    func handleFanScroll(_ event: NSEvent, order: [String]) -> Bool {
        guard !isExpanded else { return false } // the hub's ScrollView owns scrolls
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            return handleSpinScroll(event, order: order)
        }
        if event.phase == .began { scrollAccumulator = 0 }
        // One flick = one step: swallow the momentum tail so it neither
        // multi-steps the fan nor scrolls whatever sits beneath the panel.
        guard event.momentumPhase == [] else { return true }
        scrollAccumulator += event.scrollingDeltaX
        if abs(scrollAccumulator) >= 28 {
            let direction = scrollAccumulator > 0 ? 1 : -1
            scrollAccumulator = 0
            withAnimation(HubbyAnim.fanCycle) {
                pinnedTopID = FanRotation.cycled(order, from: pinnedTopID, direction: direction)
            }
            armPinReset()
        }
        if event.phase == .ended || event.phase == .cancelled { scrollAccumulator = 0 }
        return true
    }

    /// The fidget spin: vertical scroll over the orb rotates the flower
    /// freely (momentum deltas included — the trackpad supplies the
    /// physics). A short quiet spell settles it: snap to the nearest 60°
    /// and commit whichever icon reached twelve o'clock as the pin, so
    /// the spin's outcome and the fan cycle always agree.
    private func handleSpinScroll(_ event: NSEvent, order: [String]) -> Bool {
        guard abs(event.scrollingDeltaY) > 0.4, !order.isEmpty else { return false }
        orbSpin += event.scrollingDeltaY * 1.4
        spinSettleTask?.cancel()
        spinSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            self?.settleSpin(order: order)
        }
        return true
    }

    private func settleSpin(order: [String]) {
        let count = max(order.count, 1)
        let steps = Int((orbSpin / 60).rounded())
        withAnimation(HubbyAnim.fanCycle) { orbSpin = Double(steps) * 60 }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard let self, !self.isExpanded else { return }
            // Icon i sits at twelve when i*60 + spin ≡ 0 (mod 360); commit
            // it as pin and zero the spin in one transaction — the rotated
            // order at spin 0 renders the identical frame.
            let displayed = FanRotation.rotatedIDs(order, top: self.pinnedTopID)
            let index = ((-steps) % count + count) % count
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.orbSpin = 0
                self.pinnedTopID = displayed[index]
            }
            self.armPinReset()
        }
    }

    /// Trackpad pinch over the collapsed orb: pinch-in squeezes the flower
    /// (pure toy — it springs back), a decisive pinch-out blooms the hub.
    func handleMagnify(_ event: NSEvent) {
        guard !isExpanded else { return }
        orbPinch += event.magnification
        if event.phase == .ended || event.phase == .cancelled {
            if orbPinch > 0.25 {
                orbPinch = 0
                withAnimation(HubbyAnim.morph) { setExpanded(true) }
            } else {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { orbPinch = 0 }
            }
        }
    }

    /// While collapsed, an untouched pin drifts back to the smart order.
    private func armPinReset() {
        pinResetTask?.cancel()
        pinResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, !self.isExpanded else { return }
            withAnimation(HubbyAnim.fanCycle) { self.pinnedTopID = nil }
        }
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

    /// The visible content (orb or hub) in screen coordinates — the panel
    /// frame is mostly transparent margin, so hit decisions use this rect.
    private func screenContentRect() -> NSRect {
        guard let panel else { return .zero }
        let size = visibleContentSize
        let pad = HubbyMetrics.panelPadding
        return NSRect(
            x: panel.frame.minX + pad,
            y: panel.frame.maxY - pad - size.height,
            width: size.width, height: size.height)
    }

    /// Clicking anywhere in another app collapses the hub. AppKit skips
    /// physical clicks on our own windows here, but CGEvent-posted clicks
    /// (automation, accessibility tools) are delivered regardless of where
    /// they land — so anything inside the visible hub is filtered manually.
    private func updateOutsideClickMonitor() {
        if isExpanded {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                // Windowless monitor events carry screen coordinates.
                let location = event.window?.convertPoint(toScreen: event.locationInWindow)
                    ?? event.locationInWindow
                Task { @MainActor in
                    guard let self, !self.screenContentRect().insetBy(dx: -4, dy: -4).contains(location)
                    else { return }
                    withAnimation(HubbyAnim.morph) { self.setExpanded(false) }
                }
            }
        } else if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
