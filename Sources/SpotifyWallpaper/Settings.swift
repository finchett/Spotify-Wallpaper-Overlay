import Foundation

/// Small persisted preferences (UserDefaults).
enum Settings {
    private static let menuBarKey = "showMenuBarIcon"
    private static let dockKey = "showDockIcon"
    private static let missionControlBakeKey = "bakeInMissionControl"
    private static let hideWhenIdleKey = "hideOverlayWhenIdle"
    private static let hideFrameWhenIdleKey = "hideFrameWhenIdle"
    private static let vibrantColorsKey = "useVibrantColors"

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

    private static func boolOrTrue(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? true : UserDefaults.standard.bool(forKey: key)
    }
}
