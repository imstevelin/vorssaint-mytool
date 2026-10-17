// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 imstevelin
import AppKit

// Original vector composition using Apple's Command glyph, rendered at every size.
func render(size: Int, tile: Bool, output: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    if tile {
        let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
        let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 30
        shadow.shadowOffset = NSSize(width: 0, height: -16)
        shadow.set()
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(colors: [NSColor(calibratedWhite: 0.27, alpha: 1),
                           NSColor(calibratedWhite: 0.13, alpha: 1)])!
            .draw(in: path, angle: -70)
        NSColor.white.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 3
        path.stroke()
    }
    let symbol = NSImage(systemSymbolName: "command", accessibilityDescription: "Command")!
        .withSymbolConfiguration(.init(pointSize: 550, weight: .medium))!
        .withSymbolConfiguration(.init(paletteColors: [tile ? .white : .black]))!
    let glyph = NSRect(x: tile ? 255 : 100, y: tile ? 255 : 100,
                       width: tile ? 514 : 824, height: tile ? 514 : 824)
    NSGraphicsContext.saveGraphicsState()
    if tile {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 10
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
    }
    symbol.draw(in: glyph)
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
}
try! FileManager.default.createDirectory(atPath: "Resources/ForkBrand", withIntermediateDirectories: true)
render(size: 1024, tile: true, output: "Resources/ForkBrand/AppIcon.png")
render(size: 512, tile: false, output: "Resources/ForkBrand/BrandMark.png")
render(size: 18, tile: false, output: "Resources/ForkBrand/MenuBarIcon.png")
render(size: 36, tile: false, output: "Resources/ForkBrand/MenuBarIcon@2x.png")
