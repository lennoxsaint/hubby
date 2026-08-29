import SwiftUI

/// The mascot as live vectors (mirrors `OctopusGlyph.draw`, which stays the
/// menu-bar/AppKit rendition). Being a Canvas, it can move: `splay` flares
/// the outer arms outward — 0 at rest, 1 fully "excited". The hub's
/// wordmark plays a barely-there splay wiggle when the hub opens.
struct OctopusView: View {
    var size: CGFloat
    /// 0 = rest; 1 = outer arms flared a touch outward (a few degrees and
    /// a hair of sideways drift — subtle by design).
    var splay: CGFloat = 0

    private static let blush = Color(red: 0.91, green: 0.62, blue: 0.69)
    private static let ink = Color(red: 0.30, green: 0.16, blue: 0.20)

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) * (1 - 2 / 36)
            let ox = (canvasSize.width - s) / 2
            let oy = (canvasSize.height - s) / 2
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: ox + x * s, y: oy + y * s)
            }

            // Arms first (they tuck under the head). Outer arms tilt ±18°
            // at rest; splay adds up to 5° and a 1% outward drift.
            for (cx, tilt, direction) in [(0.30, -18.0, -1.0), (0.50, 0.0, 0.0), (0.70, 18.0, 1.0)] {
                let angle = Angle.degrees(tilt + direction * 5 * Double(splay))
                let pivot = pt(CGFloat(cx) + CGFloat(direction) * 0.01 * splay, 0.70)
                var arm = Path(
                    roundedRect: CGRect(
                        x: -0.065 * s, y: -0.08 * s, width: 0.13 * s, height: 0.32 * s),
                    cornerRadius: 0.065 * s)
                arm = arm.applying(CGAffineTransform(rotationAngle: angle.radians))
                    .applying(CGAffineTransform(translationX: pivot.x, y: pivot.y))
                ctx.fill(arm, with: .color(Self.blush))
            }

            // Round dome.
            ctx.fill(
                Path(ellipseIn: CGRect(
                    x: ox + 0.14 * s, y: oy + 0.06 * s, width: 0.72 * s, height: 0.66 * s)),
                with: .color(Self.blush))

            // Solid ink eyes with white glints.
            let eye = 0.15 * s
            for ex in [0.30, 0.55] {
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: ox + CGFloat(ex) * s, y: oy + 0.33 * s, width: eye, height: eye)),
                    with: .color(Self.ink))
            }
            let glint = 0.055 * s
            for gx in [0.325, 0.575] {
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: ox + CGFloat(gx) * s, y: oy + 0.33 * s, width: glint, height: glint)),
                    with: .color(.white))
            }

            // A tiny smile bulging downward.
            var smile = Path()
            smile.addArc(
                center: pt(0.5, 0.48), radius: 0.10 * s,
                startAngle: .degrees(35), endAngle: .degrees(145), clockwise: false)
            ctx.stroke(
                smile, with: .color(Self.ink),
                style: StrokeStyle(lineWidth: 0.055 * s, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}
