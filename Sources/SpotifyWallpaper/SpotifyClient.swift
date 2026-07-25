import Foundation

struct NowPlaying: Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let artworkURL: String
}

/// Reads the currently playing track from the local Spotify desktop app via AppleScript.
/// No OAuth, no network — but only reports while Spotify.app is running.
final class SpotifyClient {
    // Guarded so we never *launch* Spotify: we bail out unless the process already exists.
    private let source = """
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

    func fetch() -> NowPlaying? {
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
