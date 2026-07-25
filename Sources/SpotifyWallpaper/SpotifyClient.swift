import Foundation

struct NowPlaying: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkURL: String
}

enum SpotifyPlaybackProbe {
    case playing(trackID: String)
    case stopped
    case unavailable
}

/// Reads the currently playing track from the local Spotify desktop app via AppleScript.
/// No OAuth, no network — but only reports while Spotify.app is running.
final class SpotifyClient {
    private let queue = DispatchQueue(
        label: "com.spotifywallpaper.spotify-client",
        qos: .userInitiated)

    // Keep the frequent probe small. Metadata is fetched separately only when the
    // track id changes.
    private let probeSource = """
    tell application "System Events"
        set spotifyRunning to (exists (processes whose name is "Spotify"))
    end tell
    if not spotifyRunning then return "stopped"
    tell application "Spotify"
        if player state is not playing then return "stopped"
        return "playing" & linefeed & (id of current track)
    end tell
    """

    // Guarded independently so a quit between the probe and metadata lookup never
    // causes AppleScript to launch Spotify.
    private let metadataSource = """
    tell application "System Events"
        set spotifyRunning to (exists (processes whose name is "Spotify"))
    end tell
    if not spotifyRunning then return ""
    tell application "Spotify"
        if player state is not playing then return ""
        set trackId to id of current track
        set trackName to name of current track
        set trackArtist to artist of current track
        set trackAlbum to album of current track
        set artURL to artwork url of current track
    end tell
    return trackId & linefeed & trackName & linefeed & trackArtist & linefeed & trackAlbum & linefeed & artURL
    """

    func probe(completion: @escaping (SpotifyPlaybackProbe) -> Void) {
        queue.async { [probeSource] in
            var error: NSDictionary?
            guard let apple = NSAppleScript(source: probeSource) else {
                DispatchQueue.main.async { completion(.unavailable) }
                return
            }
            let output = apple.executeAndReturnError(&error)
            guard error == nil else {
                DispatchQueue.main.async { completion(.unavailable) }
                return
            }

            let parts = (output.stringValue ?? "").components(separatedBy: "\n")
            let result: SpotifyPlaybackProbe
            if parts.first == "playing", parts.count >= 2, !parts[1].isEmpty {
                result = .playing(trackID: parts[1])
            } else {
                result = .stopped
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func fetchMetadata(completion: @escaping (NowPlaying?) -> Void) {
        queue.async { [metadataSource] in
            let result = Self.executeMetadata(source: metadataSource)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func executeMetadata(source: String) -> NowPlaying? {
        var error: NSDictionary?
        guard let apple = NSAppleScript(source: source) else { return nil }
        let output = apple.executeAndReturnError(&error)
        if error != nil { return nil }

        let parts = (output.stringValue ?? "").components(separatedBy: "\n")
        guard parts.count >= 5, !parts[0].isEmpty else { return nil }
        return NowPlaying(id: parts[0],
                          title: parts[1],
                          artist: parts[2],
                          album: parts[3],
                          artworkURL: parts[4])
    }
}
