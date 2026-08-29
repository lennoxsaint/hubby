import SwiftUI
import AppKit

/// A transparent band hugging the hub's left, right, and bottom edges that
/// moves the whole window. There is deliberately NO top band — the
/// priorities rows live against the top edge, and an invisible drag zone
/// over interactive content is how the "possessed window" bug happened.
/// The drag engages only on real movement: `performDrag` from a plain
/// mouse-down enters an event-tracking session with no mouse-up left to
/// end it, gluing the window to the cursor (the app reads as frozen).
/// Everywhere outside the bands `hitTest` returns nil so the content
/// below stays fully interactive. (`isMovableByWindowBackground` is off
/// while expanded — it stole the priorities drag.)
struct WindowDragRing: NSViewRepresentable {
    var band: CGFloat = 12

    func makeNSView(context: Context) -> DragRingNSView {
        let view = DragRingNSView()
        view.band = band
        return view
    }

    func updateNSView(_ view: DragRingNSView, context: Context) {
        view.band = band
    }
}

final class DragRingNSView: NSView {
    var band: CGFloat = 12
    private var pendingDown: NSEvent?

    /// Only the left/right/bottom bands are tangible. The view is flipped
    /// state-agnostic: compute "top" from the window's frame, not bounds
    /// orientation — insetting all sides and re-adding the top strip keeps
    /// it correct either way.
    private func inBand(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else { return false }
        guard !bounds.insetBy(dx: band, dy: band).contains(point) else { return false }
        // Exclude the strip along the visual top edge.
        let topStrip = isFlipped
            ? NSRect(x: 0, y: 0, width: bounds.width, height: band)
            : NSRect(x: 0, y: bounds.maxY - band, width: bounds.width, height: band)
        // Corners stay draggable only where they belong to a side band.
        if topStrip.contains(point) { return false }
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return inBand(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        // Arm only — a plain click must do nothing.
        pendingDown = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = pendingDown else { return }
        let a = down.locationInWindow, b = event.locationInWindow
        guard hypot(b.x - a.x, b.y - a.y) > 3 else { return }
        pendingDown = nil
        window?.performDrag(with: down)
    }

    override func mouseUp(with event: NSEvent) {
        pendingDown = nil
    }

    /// The open hand advertises the affordance before the first drag.
    override func resetCursorRects() {
        let sides = [
            NSRect(x: 0, y: 0, width: band, height: bounds.height),
            NSRect(x: bounds.maxX - band, y: 0, width: band, height: bounds.height),
            isFlipped
                ? NSRect(x: 0, y: bounds.maxY - band, width: bounds.width, height: band)
                : NSRect(x: 0, y: 0, width: bounds.width, height: band),
        ]
        for rect in sides { addCursorRect(rect, cursor: .openHand) }
    }
}
