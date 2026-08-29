import SwiftUI
import AppKit

/// A transparent ring hugging the hub's outer edge that moves the whole
/// window: mouse-down inside the band hands the event to
/// `NSWindow.performDrag`, everywhere else `hitTest` returns nil so the
/// content below stays fully interactive. This exists because
/// `isMovableByWindowBackground` is off while expanded (it stole the
/// priorities drag); the edges are the one place a drag can only mean
/// "move the board".
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

    /// Only the edge band is tangible; the interior is a hole.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return bounds.insetBy(dx: band, dy: band).contains(local) ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    /// The open hand advertises the affordance before the first drag.
    override func resetCursorRects() {
        for edge in [
            NSRect(x: 0, y: 0, width: bounds.width, height: band),
            NSRect(x: 0, y: bounds.maxY - band, width: bounds.width, height: band),
            NSRect(x: 0, y: 0, width: band, height: bounds.height),
            NSRect(x: bounds.maxX - band, y: 0, width: band, height: bounds.height),
        ] {
            addCursorRect(edge, cursor: .openHand)
        }
    }
}
