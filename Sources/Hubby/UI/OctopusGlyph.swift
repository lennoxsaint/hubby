import AppKit

/// Hubby's mascot, reduced to what 18 points can carry: a round dome, two
/// solid glinty eyes, a little smile, three stubby arms. The hub octopus —
/// one head, an arm on every thread. Eyes are DRAWN (dark ink + white
/// glint), never punched out: transparent sockets over a pink silhouette
/// read as a skull, which is the opposite of the desk-pet brief. The
/// full-color rendition lives in `packaging/make-icon.swift` (a standalone
/// script that can't import app sources, so the artwork is duplicated
/// there by design).
@MainActor
enum OctopusGlyph {
    /// Status-item image: the blush-pink octopus, deliberately NOT a
    /// template — Hubby keeps its color in the menu bar on both light and
    /// dark bars.
    static func menuBarImage() -> NSImage {
        image(size: 18)
    }

    /// The mascot at any point size (orb centre, wordmark, menu bar).
    static func image(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: size, height: size)
            .insetBy(dx: size / 36, dy: size / 36))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// The blush body ink pair (matches make-icon's palette).
    private static let blush = NSColor(calibratedRed: 0.91, green: 0.62, blue: 0.69, alpha: 1)
    private static let ink = NSColor(calibratedRed: 0.30, green: 0.16, blue: 0.20, alpha: 1)

    /// Fill `rect` with the mascot. Coordinates are y-up (AppKit).
    static func draw(in rect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let s = min(rect.width, rect.height)
        func x(_ v: CGFloat) -> CGFloat { rect.minX + v * s }
        func y(_ v: CGFloat) -> CGFloat { rect.minY + v * s }

        ctx.setFillColor(blush.cgColor)

        // Three arms splaying from under the head, outer two tilted.
        for (cx, degrees) in [(0.30, 18.0), (0.50, 0.0), (0.70, -18.0)] {
            ctx.saveGState()
            ctx.translateBy(x: x(cx), y: y(0.30))
            ctx.rotate(by: degrees * .pi / 180)
            ctx.addPath(CGPath(
                roundedRect: CGRect(
                    x: -0.065 * s, y: -0.24 * s, width: 0.13 * s, height: 0.32 * s),
                cornerWidth: 0.065 * s, cornerHeight: 0.065 * s, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Rounder, chubbier dome than before — cuteness is curvature.
        ctx.addEllipse(in: CGRect(x: x(0.14), y: y(0.28), width: 0.72 * s, height: 0.66 * s))
        ctx.fillPath()

        // Solid ink eyes…
        ctx.setFillColor(ink.cgColor)
        let eye = 0.15 * s
        ctx.addEllipse(in: CGRect(x: x(0.30), y: y(0.52), width: eye, height: eye))
        ctx.addEllipse(in: CGRect(x: x(0.55), y: y(0.52), width: eye, height: eye))
        ctx.fillPath()
        // …with white glints (top-leading catchlight).
        ctx.setFillColor(NSColor.white.cgColor)
        let glint = 0.055 * s
        ctx.addEllipse(in: CGRect(x: x(0.325), y: y(0.615), width: glint, height: glint))
        ctx.addEllipse(in: CGRect(x: x(0.575), y: y(0.615), width: glint, height: glint))
        ctx.fillPath()

        // A tiny smile between the eyes (arc bulging downward in y-up).
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(0.055 * s)
        ctx.setLineCap(.round)
        ctx.addArc(
            center: CGPoint(x: x(0.5), y: y(0.52)), radius: 0.10 * s,
            startAngle: 215 * .pi / 180, endAngle: 325 * .pi / 180, clockwise: false)
        ctx.strokePath()
    }
}
