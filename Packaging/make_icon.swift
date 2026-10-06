import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 200, yRadius: 200)
        NSGradient(starting: NSColor(red: 0.06, green: 0.12, blue: 0.22, alpha: 1),
                   ending: NSColor(red: 0.15, green: 0.33, blue: 0.42, alpha: 1))!.draw(in: background, angle: 65)
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: NSColor) {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
        }
        let silver = NSColor(red: 0.83, green: 0.91, blue: 0.95, alpha: 1)
        let dark = NSColor(red: 0.035, green: 0.065, blue: 0.10, alpha: 1)
        // A central display on a stand, flanked by exactly two speakers.
        box(473, 276, 78, 112, 12, silver)
        box(410, 250, 204, 30, 15, silver)
        box(302, 353, 420, 326, 30, silver)
        let screen = NSBezierPath(roundedRect: NSRect(x: 320, y: 393, width: 384, height: 268), xRadius: 16, yRadius: 16)
        NSGradient(starting: NSColor(red: 0.02, green: 0.23, blue: 0.41, alpha: 1),
                   ending: NSColor(red: 0.18, green: 0.88, blue: 0.85, alpha: 1))!.draw(in: screen, angle: 35)
        NSGraphicsContext.saveGraphicsState()
        screen.addClip()
        let reflection = NSBezierPath()
        reflection.move(to: NSPoint(x: 320, y: 393)); reflection.line(to: NSPoint(x: 704, y: 661))
        reflection.line(to: NSPoint(x: 320, y: 661)); reflection.close()
        NSColor(white: 1, alpha: 0.13).setFill(); reflection.fill()
        NSGraphicsContext.restoreGraphicsState()
        box(496, 365, 32, 8, 4, dark.withAlphaComponent(0.4))
        for x: CGFloat in [155, 747] {
            box(x, 325, 122, 386, 24, silver)
            box(x + 9, 334, 104, 368, 17, dark)
            // Small tweeter above the large woofer.
            for (y, diameter): (CGFloat, CGFloat) in [(605, 42), (394, 82)] {
                let rect = NSRect(x: x + (122 - diameter) / 2, y: y, width: diameter, height: diameter)
                NSColor(red: 0.40, green: 0.56, blue: 0.62, alpha: 1).setFill()
                NSBezierPath(ovalIn: rect).fill()
                dark.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6)).fill()
                NSColor(red: 0.18, green: 0.71, blue: 0.72, alpha: 1).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: diameter * 0.33, dy: diameter * 0.33)).fill()
            }
            box(x + 44, 352, 34, 5, 2.5, silver.withAlphaComponent(0.45))
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
