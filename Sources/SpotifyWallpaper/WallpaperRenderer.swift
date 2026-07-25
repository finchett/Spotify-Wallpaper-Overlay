import AppKit

/// Composes the "now playing" wallpaper: a vibrant gradient background derived from the
/// cover, a centered rounded album card with a soft shadow, and title/artist text
/// anchored to the bottom-left — mirroring Spotify's full-screen canvas.
final class WallpaperRenderer {
    /// Height of the solid black bar drawn behind the menu bar, in device pixels.
    var menuBarHeightPixels: CGFloat = 74
    /// Radius of the black rounded-corner mask, in device pixels.
    var screenCornerRadiusPixels: CGFloat = 44

    func render(cover: NSImage, title: String, artist: String, size: CGSize, scale: CGFloat) -> NSBitmapImageRep? {
        let pixelsWide = Int(size.width * scale)
        let pixelsHigh = Int(size.height * scale)
        guard pixelsWide > 0, pixelsHigh > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixelsWide,
                                         pixelsHigh: pixelsHigh,
                                         bitsPerSample: 8,
                                         samplesPerPixel: 4,
                                         hasAlpha: true,
                                         isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0,
                                         bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = size   // draw in point space; the context scales to pixels

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let cg = ctx.cgContext
        defer { NSGraphicsContext.restoreGraphicsState() }

        // The context's coordinate space is in pixels, but we lay everything out in
        // points. Scale by the backing factor so point-based drawing fills the whole
        // pixel buffer (otherwise on a 2× display it covers only the bottom-left quarter).
        cg.scaleBy(x: scale, y: scale)

        let W = size.width, H = size.height
        let bounds = CGRect(x: 0, y: 0, width: W, height: H)

        // Background: vibrant color, darkened, top→bottom gradient.
        let base = ColorExtractor.vibrant(from: cover)
        let top = adjust(base, brightness: 0.42, saturationScale: 0.9)
        let bottom = adjust(base, brightness: 0.20, saturationScale: 0.95)
        if let gradient = NSGradient(starting: top, ending: bottom) {
            gradient.draw(in: bounds, angle: -90)   // start color at the top
        } else {
            bottom.setFill()
            bounds.fill()
        }

        // Album card, centered with a slight upward bias.
        let cardSize = min(H * 0.46, W * 0.40)
        let cardRect = CGRect(x: (W - cardSize) / 2,
                              y: (H - cardSize) / 2 + H * 0.02,
                              width: cardSize,
                              height: cardSize)
        let cornerRadius = cardSize * 0.03
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: cornerRadius, yRadius: cornerRadius)

        // Soft drop shadow behind an opaque white backing (so the corners stay clean).
        cg.saveGState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = cardSize * 0.06
        shadow.shadowOffset = NSSize(width: 0, height: -cardSize * 0.02)
        shadow.set()
        NSColor.white.setFill()
        cardPath.fill()
        cg.restoreGState()

        // Cover art, clipped to the rounded card, aspect-filled.
        cg.saveGState()
        cardPath.addClip()
        drawAspectFill(cover, in: cardRect)
        cg.restoreGState()

        // Title + artist, bottom-left.
        let margin = W * 0.045
        let titleSize = max(22, H * 0.032)
        let artistSize = max(15, H * 0.020)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: titleSize, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let artistAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: artistSize, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.65),
        ]

        let artistY = H * 0.06
        let titleY = artistY + artistSize * 1.6
        NSAttributedString(string: artist, attributes: artistAttrs)
            .draw(at: CGPoint(x: margin, y: artistY))
        NSAttributedString(string: title, attributes: titleAttrs)
            .draw(at: CGPoint(x: margin, y: titleY))

        // Overlays, drawn last so they always win. Values are in device pixels; the
        // context is scaled to points, so divide by `scale`.
        NSColor.black.setFill()

        // Solid black bar behind the menu bar (top of the screen = top of the buffer).
        let barHeight = menuBarHeightPixels / scale
        CGRect(x: 0, y: H - barHeight, width: W, height: barHeight).fill()

        // Black rounded corners on the content region *below* the bar, so the top
        // corners sit at the bar's bottom edge (not the physical screen top).
        let radius = screenCornerRadiusPixels / scale
        let contentRect = CGRect(x: 0, y: 0, width: W, height: H - barHeight)
        let corners = NSBezierPath(rect: contentRect)
        corners.append(NSBezierPath(roundedRect: contentRect, xRadius: radius, yRadius: radius))
        corners.windingRule = .evenOdd
        corners.fill()

        return rep
    }

    /// Reproduces a color's hue but forces a target brightness / scaled saturation.
    private func adjust(_ color: NSColor, brightness: CGFloat, saturationScale: CGFloat) -> NSColor {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(deviceHue: h,
                       saturation: min(1, s * saturationScale),
                       brightness: brightness,
                       alpha: 1)
    }

    private func drawAspectFill(_ image: NSImage, in rect: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(x: rect.midX - drawSize.width / 2,
                              y: rect.midY - drawSize.height / 2,
                              width: drawSize.width,
                              height: drawSize.height)
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
}
