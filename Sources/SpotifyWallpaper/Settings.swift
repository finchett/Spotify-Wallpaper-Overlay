import Foundation

enum MediaDisplayMode: String, CaseIterable, Identifiable {
    case canvasWhenAvailable
    case artworkOnly

    var id: Self { self }
}

enum SongInfoVisibility: String, CaseIterable, Identifiable {
    case briefly
    case always
    case never

    var id: Self { self }
}

enum SongInfoPosition: String, CaseIterable, Identifiable {
    case bottomLeft
    case bottomRight
    case topLeft
    case topRight
    case center

    var id: Self { self }
}

enum SongInfoSize: String, CaseIterable, Identifiable {
    case small
    case standard
    case large

    var id: Self { self }
}

/// Small persisted preferences (UserDefaults).
enum Settings {
    private static let menuBarKey = "showMenuBarIcon"
    private static let dockKey = "showDockIcon"
    private static let missionControlBakeKey = "bakeInMissionControl"
    private static let hideWhenIdleKey = "hideOverlayWhenIdle"
    private static let hideFrameWhenIdleKey = "hideFrameWhenIdle"
    private static let vibrantColorsKey = "useVibrantColors"
    private static let mediaDisplayModeKey = "mediaDisplayMode"
    private static let songInfoVisibilityKey = "songInfoVisibility"
    private static let songInfoPositionKey = "songInfoPosition"
    private static let songInfoSizeKey = "songInfoSize"
    private static let clickToRevealSongInfoKey = "clickToRevealSongInfo"

    /// Whether the menu-bar icon is shown. Defaults to true on first run.
    static var showMenuBarIcon: Bool {
        get { boolOrTrue(menuBarKey) }
        set { UserDefaults.standard.set(newValue, forKey: menuBarKey) }
    }

    /// Whether the app shows a Dock icon (vs. running as a background agent).
    static var showDockIcon: Bool {
        get { boolOrTrue(dockKey) }
        set { UserDefaults.standard.set(newValue, forKey: dockKey) }
    }

    /// Opt-in because this temporarily changes the system wallpaper store.
    static var bakeInMissionControl: Bool {
        get { UserDefaults.standard.bool(forKey: missionControlBakeKey) }
        set { UserDefaults.standard.set(newValue, forKey: missionControlBakeKey) }
    }

    /// Whether the entire overlay disappears when Spotify is not playing.
    static var hideOverlayWhenIdle: Bool {
        get { UserDefaults.standard.bool(forKey: hideWhenIdleKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideWhenIdleKey) }
    }

    /// Whether idle hiding also removes the always-on black framing.
    static var hideFrameWhenIdle: Bool {
        get { UserDefaults.standard.bool(forKey: hideFrameWhenIdleKey) }
        set { UserDefaults.standard.set(newValue, forKey: hideFrameWhenIdleKey) }
    }

    static var useVibrantColors: Bool {
        get { UserDefaults.standard.bool(forKey: vibrantColorsKey) }
        set { UserDefaults.standard.set(newValue, forKey: vibrantColorsKey) }
    }

    static var mediaDisplayMode: MediaDisplayMode {
        get {
            rawValue(
                mediaDisplayModeKey,
                default: MediaDisplayMode.canvasWhenAvailable)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: mediaDisplayModeKey) }
    }

    static var songInfoVisibility: SongInfoVisibility {
        get {
            rawValue(
                songInfoVisibilityKey,
                default: SongInfoVisibility.briefly)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: songInfoVisibilityKey) }
    }

    static var songInfoPosition: SongInfoPosition {
        get {
            rawValue(
                songInfoPositionKey,
                default: SongInfoPosition.bottomLeft)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: songInfoPositionKey) }
    }

    static var songInfoSize: SongInfoSize {
        get {
            rawValue(songInfoSizeKey, default: SongInfoSize.standard)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: songInfoSizeKey) }
    }

    static var clickToRevealSongInfo: Bool {
        get { UserDefaults.standard.bool(forKey: clickToRevealSongInfoKey) }
        set { UserDefaults.standard.set(newValue, forKey: clickToRevealSongInfoKey) }
    }

    private static func boolOrTrue(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }

    private static func rawValue<Value: RawRepresentable>(
        _ key: String,
        default defaultValue: Value
    ) -> Value where Value.RawValue == String {
        guard let value = UserDefaults.standard.string(forKey: key),
              let result = Value(rawValue: value) else {
            return defaultValue
        }
        return result
    }
}
