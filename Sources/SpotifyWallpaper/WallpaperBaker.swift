import AppKit

/// An opt-in, crash-recoverable transaction that replaces the all-Spaces wallpaper
/// while Spotify is playing. The original store remains untouched in a durable recovery
/// file until playback stops or the feature is disabled.
final class WallpaperBaker {
    private var tempURLs: [URL] = []
    private(set) var isBaked = false

    private let directory: URL
    private let legacyRecoveryURL: URL
    private let wallpaperStoreURL: URL
    private let recoveryURL: URL

    init() {
        directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpotifyWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        recoveryURL = directory.appendingPathComponent(
            "wallpaper-store-recovery.plist")
        legacyRecoveryURL = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpotifyWallpaper", isDirectory: true)
            .appendingPathComponent("wallpaper-store-recovery.plist")
        wallpaperStoreURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/com.apple.wallpaper/Store/Index.plist")

        recoverInterruptedBake()
    }

    func bake(_ snapshots: [(screen: NSScreen, image: NSImage)]) {
        guard !snapshots.isEmpty else { return }

        let writtenURLs = snapshots.compactMap { snapshot -> URL? in
            guard let data = pngData(snapshot.image) else { return nil }
            let url = directory.appendingPathComponent(
                "bake-\(UUID().uuidString).png")
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }
        guard let mainImageURL = writtenURLs.first else { return }

        guard let originalData = originalWallpaperStore() else {
            removeImages(writtenURLs)
            return
        }

        guard bakeAllSpaces(using: mainImageURL, originalData: originalData) else {
            removeImages(writtenURLs)
            return
        }

        let oldURLs = tempURLs
        tempURLs = writtenURLs
        isBaked = true
        removeImages(oldURLs)
    }

    func restore() {
        guard isBaked ||
                FileManager.default.fileExists(atPath: recoveryURL.path) else {
            return
        }
        guard restoreAllSpacesStore() else { return }
        isBaked = false
        removeTemporaryImages()
    }

    /// Captures the real wallpaper exactly once per playback session. Subsequent track
    /// changes always rebuild from these original bytes, never from a prior baked store.
    private func originalWallpaperStore() -> Data? {
        if let saved = try? Data(contentsOf: recoveryURL) {
            return saved
        }
        guard FileManager.default.fileExists(atPath: wallpaperStoreURL.path),
              let originalData = try? Data(contentsOf: wallpaperStoreURL) else {
            return nil
        }
        do {
            try originalData.write(to: recoveryURL, options: .atomic)
            return originalData
        } catch {
            return nil
        }
    }

    private func bakeAllSpaces(using imageURL: URL, originalData: Data) -> Bool {
        guard var root = try? PropertyListSerialization.propertyList(
                from: originalData,
                options: [],
                format: nil) as? [String: Any],
              let originalSettings =
                (root["AllSpacesAndDisplays"] as? [String: Any]) ??
                (root["SystemDefault"] as? [String: Any]) else {
            return false
        }

        do {
            let desktop = bakedDesktop(
                copying: originalSettings["Desktop"] as? [String: Any],
                imageURL: imageURL)
            var allSpaces = originalSettings
            allSpaces["Desktop"] = desktop
            allSpaces["Type"] = "individual"

            var systemDefault =
                (root["SystemDefault"] as? [String: Any]) ?? originalSettings
            systemDefault["Desktop"] = desktop
            systemDefault["Type"] = "individual"

            root["AllSpacesAndDisplays"] = allSpaces
            root["SystemDefault"] = systemDefault

            // These dictionaries override AllSpacesAndDisplays. Clearing them only for
            // the transaction forces every existing Space to use the baked image.
            root["Displays"] = [String: Any]()
            root["Spaces"] = [String: Any]()

            let bakedData = try PropertyListSerialization.data(
                fromPropertyList: root,
                format: .binary,
                options: 0)
            try writeWallpaperStore(bakedData)
            restartWallpaperAgent()
            return true
        } catch {
            // Keep the durable recovery file so restore() or the next launch can retry.
            return false
        }
    }

    private func bakedDesktop(
        copying original: [String: Any]?,
        imageURL: URL
    ) -> [String: Any] {
        var desktop = original ?? [:]
        var content = desktop["Content"] as? [String: Any] ?? [:]
        var choices = content["Choices"] as? [[String: Any]] ?? [[:]]
        if choices.isEmpty { choices = [[:]] }

        let fileURL = imageURL.absoluteString
        let configuration: [String: Any] = [
            "type": "imageFile",
            "url": ["relative": fileURL],
        ]
        let encodedConfiguration =
            (try? PropertyListSerialization.data(
                fromPropertyList: configuration,
                format: .binary,
                options: 0)) ?? Data()

        choices[0]["Provider"] = "com.apple.wallpaper.choice.image"
        choices[0]["Configuration"] = encodedConfiguration
        // Native current-macOS image records keep this empty. Adding a bare URL here
        // makes WallpaperImageExtension reject the choice with Cocoa error 4865.
        choices[0]["Files"] = [[String: Any]]()
        content["Choices"] = choices
        content["Shuffle"] = "$null"

        let now = Date()
        desktop["Content"] = content
        desktop["LastSet"] = now
        desktop["LastUse"] = now
        return desktop
    }

    private func restoreAllSpacesStore() -> Bool {
        guard let originalData = try? Data(contentsOf: recoveryURL) else {
            return false
        }
        do {
            try writeWallpaperStore(originalData)
            restartWallpaperAgent()
            try FileManager.default.removeItem(at: recoveryURL)
            return true
        } catch {
            // Retain the marker, original bytes, and temporary images for a later retry.
            return false
        }
    }

    private func recoverInterruptedBake() {
        if FileManager.default.fileExists(atPath: recoveryURL.path) {
            guard restoreAllSpacesStore() else { return }
        } else if let legacyData = try? Data(contentsOf: legacyRecoveryURL) {
            do {
                try writeWallpaperStore(legacyData)
                restartWallpaperAgent()
                try FileManager.default.removeItem(at: legacyRecoveryURL)
            } catch {
                return
            }
        }
        removeOrphanedBakeImages()
    }

    private func writeWallpaperStore(_ data: Data) throws {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: wallpaperStoreURL.path)
        try data.write(to: wallpaperStoreURL, options: .atomic)
        if let permissions = attributes?[.posixPermissions] {
            try? FileManager.default.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: wallpaperStoreURL.path)
        }
    }

    private func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        // SIGKILL prevents the old agent from flushing its in-memory baked state over
        // the store we just wrote before launchd starts a fresh instance.
        process.arguments = ["-KILL", "WallpaperAgent"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private func removeTemporaryImages() {
        removeImages(tempURLs)
        tempURLs.removeAll()
    }

    private func removeImages(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeOrphanedBakeImages() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil) else {
            return
        }
        for url in files where
            url.lastPathComponent.hasPrefix("bake-") &&
            url.pathExtension == "png" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}
