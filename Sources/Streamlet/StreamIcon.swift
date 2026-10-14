import AppKit

/// A small water drop above two flowing waves ("小溪").
enum StreamIcon {
    static func draw(in rect: NSRect, color: NSColor) {
        let s = min(rect.width, rect.height) / 18
        let ox = rect.minX + (rect.width - 18 * s) / 2, oy = rect.minY + (rect.height - 18 * s) / 2
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * s, y: oy + y * s) }
        color.set()

        let drop = NSBezierPath()
        drop.move(to: p(9, 17.4))
        drop.curve(to: p(9, 8.6), controlPoint1: p(11.2, 14.4), controlPoint2: p(13.2, 8.6))
        drop.curve(to: p(9, 17.4), controlPoint1: p(4.8, 8.6), controlPoint2: p(6.8, 14.4))
        drop.close()
        drop.fill()

        for (y, inset) in [(CGFloat(5.6), CGFloat(1.0)), (CGFloat(1.8), CGFloat(2.6))] {
            let wave = NSBezierPath()
            wave.lineWidth = 1.7 * s
            wave.lineCapStyle = .round
            let x0 = inset, x1 = 18 - inset, seg = (x1 - x0) / 3
            wave.move(to: p(x0, y))
            for i in 0..<3 {
                let a = x0 + CGFloat(i) * seg
                let up: CGFloat = i % 2 == 0 ? 1.5 : -1.5
                wave.curve(to: p(a + seg, y), controlPoint1: p(a + seg * 0.35, y + up), controlPoint2: p(a + seg * 0.65, y + up))
            }
            wave.stroke()
        }
    }

    static func image(size: CGFloat, template: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, color: template ? .black : NSColor(red: 0.16, green: 0.62, blue: 0.85, alpha: 1))
            return true
        }
        img.isTemplate = template
        return img
    }

    /// Renders the app icon (rounded tile + white stream glyph) as PNG.
    static func appIconPNG(pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let full = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let tile = full.insetBy(dx: CGFloat(pixels) * 0.1, dy: CGFloat(pixels) * 0.1)
        let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
        NSGradient(starting: NSColor(red: 0.29, green: 0.78, blue: 0.95, alpha: 1),
                   ending: NSColor(red: 0.10, green: 0.42, blue: 0.80, alpha: 1))?.draw(in: path, angle: -90)
        draw(in: tile.insetBy(dx: tile.width * 0.2, dy: tile.width * 0.2), color: .white)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
