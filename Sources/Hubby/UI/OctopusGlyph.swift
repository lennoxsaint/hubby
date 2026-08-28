import AppKit

/// Hubby's mascot, reduced to what 18 points can carry: a chubby dome, two
/// punched-out eyes, three stubby arms. The hub octopus — one head, an arm
/// on every thread. The full-color rendition lives in
/// `packaging/make-icon.swift` (a standalone script that can't import app
/// sources, so the artwork is duplicated there by design).
@MainActor
enum OctopusGlyph {
    /// Status-item image: black-on-clear template, so the system tints it
    /// for light/dark menu bars automatically.
    static func menuBarImage() -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        draw(silhouetteIn: NSRect(x: 0, y: 0, width: size, height: size)
            .insetBy(dx: 0.5, dy: 0.5))
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// Fill `rect` with the simplified silhouette. Only alpha matters —
    /// template rendering discards color, and the eye cutouts read against
    /// any menu bar tint.
    static func draw(silhouetteIn rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = min(rect.width, rect.height)
        func x(_ v: CGFloat) -> CGFloat { rect.minX + v * s }
        func y(_ v: CGFloat) -> CGFloat { rect.minY + v * s }

        ctx.setFillColor(NSColor.black.cgColor)

        // Chubby head dome.
        ctx.addEllipse(in: CGRect(x: x(0.17), y: y(0.32), width: 0.66 * s, height: 0.60 * s))
        ctx.fillPath()

        // Three arms splaying from under the head, outer two tilted.
        for (cx, degrees) in [(0.30, 18.0), (0.50, 0.0), (0.70, -18.0)] {
            ctx.saveGState()
            ctx.translateBy(x: x(cx), y: y(0.30))
            ctx.rotate(by: degrees * .pi / 180)
            ctx.addPath(CGPath(
                roundedRect: CGRect(
                    x: -0.065 * s, y: -0.26 * s, width: 0.13 * s, height: 0.34 * s),
                cornerWidth: 0.065 * s, cornerHeight: 0.065 * s, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Eyes, punched out of the silhouette.
        ctx.setBlendMode(.destinationOut)
        ctx.addEllipse(in: CGRect(x: x(0.335), y: y(0.52), width: 0.115 * s, height: 0.115 * s))
        ctx.addEllipse(in: CGRect(x: x(0.55), y: y(0.52), width: 0.115 * s, height: 0.115 * s))
        ctx.fillPath()
        ctx.setBlendMode(.normal)
    }
}
