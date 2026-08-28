// Renders Hubby's app icon: the chubby octopus mascot on ink-black glass
// with a violet rim light — one head (the hub), arms holding glowing
// threads in the status colors. The mascot's silhouette twin lives in
// Sources/Hubby/UI/OctopusGlyph.swift; this script can't import app
// sources, so the artwork is duplicated by design.
// Run via `make icon` (swift packaging/make-icon.swift <out.iconset dir>).
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.iconset>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let violet = NSColor(calibratedRed: 0.557, green: 0.486, blue: 1.0, alpha: 1)
let violetDeep = NSColor(calibratedRed: 0.42, green: 0.35, blue: 0.85, alpha: 1)
let ink = NSColor(calibratedRed: 0.078, green: 0.078, blue: 0.11, alpha: 1)

/// A tapered arm: a curve stroked round-capped, thick at the shoulder.
func strokeArm(
    _ ctx: CGContext, from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint,
    width: CGFloat, color: NSColor
) {
    let path = CGMutablePath()
    path.move(to: from)
    path.addCurve(to: to, control1: c1, control2: c2)
    ctx.addPath(path)
    ctx.setLineCap(.round)
    ctx.setLineWidth(width)
    ctx.setStrokeColor(color.cgColor)
    ctx.strokePath()
}

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    let inset = s * 0.05 // macOS icon grid margin
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.21, yRadius: s * 0.21)

    // Background: ink-black glass.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.063, green: 0.063, blue: 0.094, alpha: 1),
        NSColor(calibratedRed: 0.024, green: 0.024, blue: 0.035, alpha: 1),
    ])!.draw(in: squircle, angle: -70)

    squircle.addClip()

    // Soft glass sheen up top.
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.12),
        NSColor.white.withAlphaComponent(0.0),
    ])!.draw(in: NSRect(x: 0, y: s * 0.6, width: s, height: s * 0.4), angle: -90)

    // Tiny sizes carry head + eyes only; detail below this just smears.
    let detailed = s > 32

    if detailed {
        // Threads: three glowing lines the front arms hold, in the status
        // colors (running green, needs-you orange, unread blue).
        let threads: [(from: CGPoint, c: CGPoint, to: CGPoint, color: NSColor)] = [
            (p(0.245, 0.315), p(0.16, 0.26), p(0.135, 0.185),
             NSColor(calibratedRed: 0.20, green: 0.82, blue: 0.48, alpha: 1)),
            (p(0.50, 0.255), p(0.50, 0.20), p(0.50, 0.145),
             NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.18, alpha: 1)),
            (p(0.755, 0.315), p(0.84, 0.26), p(0.865, 0.185),
             NSColor(calibratedRed: 0.353, green: 0.635, blue: 1.0, alpha: 1)),
        ]
        for t in threads {
            ctx.saveGState()
            ctx.setShadow(
                offset: .zero, blur: s * 0.03,
                color: t.color.withAlphaComponent(0.85).cgColor)
            let line = CGMutablePath()
            line.move(to: t.from)
            line.addQuadCurve(to: t.to, control: t.c)
            ctx.addPath(line)
            ctx.setLineCap(.round)
            ctx.setLineWidth(s * 0.016)
            ctx.setStrokeColor(t.color.cgColor)
            ctx.strokePath()
            // The little bead at the thread's end.
            let r = s * 0.022
            ctx.addEllipse(in: CGRect(x: t.to.x - r, y: t.to.y - r, width: r * 2, height: r * 2))
            ctx.setFillColor(t.color.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Back arms, darker, peeking from behind the head.
        strokeArm(
            ctx, from: p(0.36, 0.50), c1: p(0.22, 0.44), c2: p(0.15, 0.40),
            to: p(0.115, 0.46), width: s * 0.055, color: violetDeep)
        strokeArm(
            ctx, from: p(0.64, 0.50), c1: p(0.78, 0.44), c2: p(0.85, 0.40),
            to: p(0.885, 0.46), width: s * 0.055, color: violetDeep)

        // Front arms: three curls reaching down to the threads.
        strokeArm(
            ctx, from: p(0.40, 0.46), c1: p(0.33, 0.36), c2: p(0.29, 0.33),
            to: p(0.245, 0.315), width: s * 0.062, color: violet)
        strokeArm(
            ctx, from: p(0.50, 0.44), c1: p(0.50, 0.36), c2: p(0.50, 0.31),
            to: p(0.50, 0.255), width: s * 0.062, color: violet)
        strokeArm(
            ctx, from: p(0.60, 0.46), c1: p(0.67, 0.36), c2: p(0.71, 0.33),
            to: p(0.755, 0.315), width: s * 0.062, color: violet)
    }

    // Head: the chubby dome, with a soft top light.
    let headRect = detailed
        ? CGRect(x: s * 0.29, y: s * 0.40, width: s * 0.42, height: s * 0.40)
        : CGRect(x: s * 0.24, y: s * 0.30, width: s * 0.52, height: s * 0.50)
    ctx.saveGState()
    ctx.addEllipse(in: headRect)
    ctx.clip()
    NSGradient(colors: [violet, violetDeep])!
        .draw(in: headRect, angle: -80)
    ctx.restoreGState()

    // Face, scaled off the head so both size branches stay cute.
    let eyeY = headRect.minY + headRect.height * 0.42
    let eyeR = headRect.width * 0.105
    for ex in [headRect.minX + headRect.width * 0.32,
               headRect.minX + headRect.width * 0.68] {
        // White of the eye.
        ctx.addEllipse(in: CGRect(x: ex - eyeR, y: eyeY - eyeR, width: eyeR * 2, height: eyeR * 2))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
        // Pupil, looking slightly up at you.
        let pr = eyeR * 0.52
        ctx.addEllipse(in: CGRect(
            x: ex - pr, y: eyeY - pr + eyeR * 0.18, width: pr * 2, height: pr * 2))
        ctx.setFillColor(ink.cgColor)
        ctx.fillPath()
        // Catchlight.
        let hr = eyeR * 0.18
        ctx.addEllipse(in: CGRect(
            x: ex + pr * 0.15, y: eyeY + eyeR * 0.35, width: hr * 2, height: hr * 2))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillPath()
    }

    if detailed {
        // Blush.
        for bx in [headRect.minX + headRect.width * 0.16,
                   headRect.minX + headRect.width * 0.84] {
            ctx.addEllipse(in: CGRect(
                x: bx - headRect.width * 0.07, y: headRect.minY + headRect.height * 0.24,
                width: headRect.width * 0.14, height: headRect.height * 0.08))
            ctx.setFillColor(NSColor(
                calibratedRed: 1.0, green: 0.55, blue: 0.65, alpha: 0.45).cgColor)
            ctx.fillPath()
        }
        // A tiny content smile.
        let smile = CGMutablePath()
        smile.move(to: CGPoint(
            x: headRect.minX + headRect.width * 0.42,
            y: headRect.minY + headRect.height * 0.24))
        smile.addQuadCurve(
            to: CGPoint(
                x: headRect.minX + headRect.width * 0.58,
                y: headRect.minY + headRect.height * 0.24),
            control: CGPoint(
                x: headRect.midX,
                y: headRect.minY + headRect.height * 0.16))
        ctx.addPath(smile)
        ctx.setLineCap(.round)
        ctx.setLineWidth(s * 0.012)
        ctx.setStrokeColor(ink.cgColor)
        ctx.strokePath()
    }

    // Violet rim light on the glass edge.
    let rim = NSBezierPath(
        roundedRect: rect.insetBy(dx: s * 0.006, dy: s * 0.006),
        xRadius: s * 0.205, yRadius: s * 0.205)
    rim.lineWidth = s * 0.012
    violet.withAlphaComponent(0.75).setStroke()
    rim.stroke()

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(image.size.width),
        pixelsHigh: Int(image.size.height), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

for (name, size) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    writePNG(draw(size: CGFloat(size)), to: outDir.appendingPathComponent("\(name).png"))
}
print("iconset written to \(outDir.path)")
