import CoreGraphics
import Foundation

/// The collapsed flower's geometry — one shared formula for rendering AND
/// tap hit-testing, so a click lands on exactly the icon it visually hits.
/// Coordinates are orb-local (top-left origin, `orbDiameter` square);
/// SwiftUI's y-down space makes the trig read straight through.
enum OrbLayout {
    static let restSize: CGFloat = 17
    static let leadBoost: CGFloat = 10
    static let ringRadius: CGFloat = 21

    /// Pinch-in pulls the ring toward the centre (floor keeps icons
    /// distinguishable); pinch-out pre-blooms slightly before the hub.
    static func radius(pinch: CGFloat) -> CGFloat {
        ringRadius * min(max(1 + pinch * 1.6, 0.22), 1.12)
    }

    /// First app at twelve o'clock, the rest clockwise; the fidget spin
    /// rides on top of the layout angle.
    static func angle(index: Int, spin: Double) -> Double {
        Double(index) * .pi / 3 - .pi / 2 + spin * .pi / 180
    }

    /// Lead-ness is continuous in angle so the enlargement hands over
    /// smoothly while the flower spins (1 at twelve o'clock, sharp falloff).
    static func lead(angle: Double) -> Double {
        pow(max(0, (cos(angle + .pi / 2) + 1) / 2), 6)
    }

    static func iconSize(index: Int, spin: Double) -> CGFloat {
        restSize + leadBoost * lead(angle: angle(index: index, spin: spin))
    }

    static func center(index: Int, spin: Double, pinch: CGFloat) -> CGPoint {
        let a = angle(index: index, spin: spin)
        let r = radius(pinch: pinch)
        let mid = HubbyMetrics.orbDiameter / 2
        return CGPoint(x: mid + r * cos(a), y: mid + r * sin(a))
    }

    /// Which displayed icon a tap at `point` (orb-local) hits, if any —
    /// nearest centre within the icon's radius plus a little slop.
    static func hitIndex(
        point: CGPoint, count: Int, spin: Double, pinch: CGFloat
    ) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for index in 0..<min(count, 6) {
            let c = center(index: index, spin: spin, pinch: pinch)
            let distance = hypot(point.x - c.x, point.y - c.y)
            let reach = iconSize(index: index, spin: spin) / 2 + 4
            if distance <= reach, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }
}
