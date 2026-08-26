// Renders Hubby's app icon: a purple-gradient squircle holding a frosted orb
// with a 3D-ish deck of cards — the collapsed-orb motif.
// Run via `make icon` (swift packaging/make-icon.swift <out.iconset dir>).
import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.iconset>\n".utf8))
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func draw(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size
    let inset = s * 0.05 // macOS icon grid margin
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: s * 0.21, yRadius: s * 0.21)

    // Background: deep purple gradient.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.86, alpha: 1),
        NSColor(calibratedRed: 0.22, green: 0.12, blue: 0.48, alpha: 1),
    ])!.draw(in: squircle, angle: -70)

    squircle.addClip()

    // Soft highlight up top.
    NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.28),
        NSColor.white.withAlphaComponent(0.0),
    ])!.draw(in: NSRect(x: 0, y: s * 0.55, width: s, height: s * 0.45), angle: -90)

    // The orb: frosted circle, slightly below center.
    let orbRadius = s * 0.30
    let orbCenter = NSPoint(x: s * 0.5, y: s * 0.47)
    let orbRect = NSRect(
        x: orbCenter.x - orbRadius, y: orbCenter.y - orbRadius,
        width: orbRadius * 2, height: orbRadius * 2)
    let orb = NSBezierPath(ovalIn: orbRect)
    NSColor.white.withAlphaComponent(0.16).setFill()
    orb.fill()
    NSColor.white.withAlphaComponent(0.55).setStroke()
    orb.lineWidth = s * 0.012
    orb.stroke()

    // Deck of three cards fanned inside the orb (recency stack).
    let cardSize = s * 0.20
    let configs: [(dx: CGFloat, dy: CGFloat, rot: CGFloat, alpha: CGFloat)] = [
        (-0.055, -0.02, -12, 0.55),
        (0.045, -0.005, 9, 0.75),
        (-0.005, 0.015, -2, 1.0),
    ]
    for c in configs {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()
        ctx.translateBy(x: orbCenter.x + c.dx * s, y: orbCenter.y + c.dy * s)
        ctx.rotate(by: c.rot * .pi / 180)
        let cardRect = CGRect(x: -cardSize / 2, y: -cardSize / 2, width: cardSize, height: cardSize)
        let card = CGPath(
            roundedRect: cardRect, cornerWidth: cardSize * 0.24,
            cornerHeight: cardSize * 0.24, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02,
                      color: NSColor.black.withAlphaComponent(0.35).cgColor)
        ctx.addPath(card)
        ctx.setFillColor(NSColor.white.withAlphaComponent(c.alpha).cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Green activity badge, top-right of the orb.
    let badgeRadius = s * 0.065
    let badgeCenter = NSPoint(
        x: orbCenter.x + orbRadius * 0.72, y: orbCenter.y + orbRadius * 0.72)
    let badge = NSBezierPath(ovalIn: NSRect(
        x: badgeCenter.x - badgeRadius, y: badgeCenter.y - badgeRadius,
        width: badgeRadius * 2, height: badgeRadius * 2))
    NSColor(calibratedRed: 0.20, green: 0.82, blue: 0.42, alpha: 1).setFill()
    badge.fill()

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
