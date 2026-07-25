import Foundation

/// Persists the Spotify `sp_dc` login cookie locally so it only has to be captured once.
/// `sp_dc` is long-lived (valid up to ~1 year), so a one-time paste is enough — the app
/// reads it automatically on every launch thereafter.
enum Credentials {
    private static let fileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpotifyWallpaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("sp_dc")
    }()

    /// Env var wins (handy for testing); otherwise the stored file.
    static func spDc() -> String? {
        if let env = ProcessInfo.processInfo.environment["SPOTIFY_SP_DC"], !env.isEmpty {
            return env
        }
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func hasStoredCookie() -> Bool { spDc() != nil }

    static func save(spDc value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        try? trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
        // Readable only by the user — it's a credential.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
