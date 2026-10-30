// Renders the LidTap app icon into an .iconset folder: indigo-to-sky squircle with a tapping hand.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSGradient(colors: [NSColor(red: 0.47, green: 0.36, blue: 1, alpha: 1), NSColor(red: 0.2, green: 0.62, blue: 1, alpha: 1)])!
        .draw(in: path, angle: -55)
    NSShadow().set()
    // Soft highlight
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: rect.width * 0.22, yRadius: rect.width * 0.22), angle: -90)
    // Ripple rings
    NSColor.white.withAlphaComponent(0.22).setStroke()
    for (r, w) in [(0.30, 0.018), (0.4, 0.012)] {
        let c = NSPoint(x: rect.midX - rect.width * 0.08, y: rect.midY + rect.height * 0.16)
        let ring = NSBezierPath(ovalIn: NSRect(x: c.x - rect.width * r / 2, y: c.y - rect.width * r / 2, width: rect.width * r, height: rect.width * r))
        ring.lineWidth = s * w
        ring.stroke()
    }
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let hand = NSImage(systemSymbolName: "hand.tap.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let size = hand.size
        hand.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - s * 0.02, width: size.width, height: size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
