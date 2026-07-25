import AppKit

/// Writes rendered wallpapers to Application Support. Every frame gets a unique path
/// because macOS caches desktop pictures by URL — reusing a path would silently skip
/// the refresh. Old frames are pruned so the folder doesn't grow forever.
enum WallpaperStore {
    private static let directory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpotifyWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func write(_ rep: NSBitmapImageRep, id: String, index: Int) -> URL? {
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        pruneOldFrames()

        let safeID = id.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let name = "wallpaper-\(index)-\(safeID)-\(Int(Date().timeIntervalSince1970)).png"
        let url = directory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Keep a handful of recent frames (enough to cover all screens' current wallpapers).
    private static func pruneOldFrames() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]) else { return }
        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }
        for stale in sorted.dropFirst(8) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
