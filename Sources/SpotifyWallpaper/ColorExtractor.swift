import AppKit

/// Extracts a single vibrant, representative color from cover art — the way Spotify
/// tints its full-screen "now playing" view. Buckets samples by hue and weights them
/// by saturation × brightness, ignoring near-white/near-black pixels.
enum ColorExtractor {
    static func vibrant(from image: NSImage) -> NSColor {
        let fallback = NSColor(deviceHue: 0, saturation: 0, brightness: 0.2, alpha: 1)
        guard let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff),
              bmp.pixelsWide > 0, bmp.pixelsHigh > 0 else { return fallback }

        let w = bmp.pixelsWide, h = bmp.pixelsHigh
        let targetSamples = 44
        let stepX = max(1, w / targetSamples)
        let stepY = max(1, h / targetSamples)

        let bucketCount = 24
        var weight = [CGFloat](repeating: 0, count: bucketCount)
        var accR = [CGFloat](repeating: 0, count: bucketCount)
        var accG = [CGFloat](repeating: 0, count: bucketCount)
        var accB = [CGFloat](repeating: 0, count: bucketCount)

        var avgR: CGFloat = 0, avgG: CGFloat = 0, avgB: CGFloat = 0, avgN: CGFloat = 0

        var y = 0
        while y < h {
            var x = 0
            while x < w {
                if let c = bmp.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                    avgR += r; avgG += g; avgB += b; avgN += 1

                    var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
                    c.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
                    if sat > 0.35 && bri > 0.25 && bri < 0.98 {
                        let i = min(bucketCount - 1, Int(hue * CGFloat(bucketCount)))
                        let wgt = sat * bri
                        weight[i] += wgt
                        accR[i] += r * wgt
                        accG[i] += g * wgt
                        accB[i] += b * wgt
                    }
                }
                x += stepX
            }
            y += stepY
        }

        var bestIndex = -1
        var bestWeight: CGFloat = 0
        for i in 0..<bucketCount where weight[i] > bestWeight {
            bestWeight = weight[i]
            bestIndex = i
        }

        if bestIndex >= 0, bestWeight > 0 {
            return NSColor(deviceRed: accR[bestIndex] / bestWeight,
                           green: accG[bestIndex] / bestWeight,
                           blue: accB[bestIndex] / bestWeight,
                           alpha: 1)
        }
        // Grayscale / low-saturation cover: fall back to the plain average.
        if avgN > 0 {
            return NSColor(deviceRed: avgR / avgN, green: avgG / avgN, blue: avgB / avgN, alpha: 1)
        }
        return fallback
    }
}
