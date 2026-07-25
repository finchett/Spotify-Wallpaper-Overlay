#!/usr/bin/env swift
// Generates an AppIcon.iconset (rounded green squircle + white music note) for iconutil.
// Usage:  swift make-icon.swift <output-iconset-dir>
import AppKit

func iconPNG(_ px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    // Rounded-square background with a vertical green gradient.
    let inset = size * 0.06
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)
    path.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.85, blue: 0.40, alpha: 1),
                        NSColor(srgbRed: 0.04, green: 0.52, blue: 0.27, alpha: 1)])!
        .draw(in: rect, angle: -90)

    // White music note, centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .bold)
    if let base = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let noteSize = base.size
        let tinted = NSImage(size: noteSize)
        tinted.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: noteSize))
        NSColor.white.set()
        NSRect(origin: .zero, size: noteSize).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: (size - noteSize.width) / 2,
                               y: (size - noteSize.height) / 2,
                               width: noteSize.width, height: noteSize.height))
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output-dir>\n".utf8))
    exit(1)
}
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename, pixel size) — the set iconutil expects.
let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in entries {
    try! iconPNG(px).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("wrote \(entries.count) icons to \(outDir)")
