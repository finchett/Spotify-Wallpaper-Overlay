import Combine

enum SettingsPage: String, CaseIterable, Identifiable {
    case display
    case songInfo
    case playback
    case missionControl
    case app

    var id: Self { self }

    var title: String {
        switch self {
        case .display: return "Display"
        case .songInfo: return "Song Info"
        case .playback: return "Playback"
        case .missionControl: return "Wallpaper Fix"
        case .app: return "App"
        }
    }
}

/// View-facing state shared between the AppDelegate (which drives everything) and the
/// SwiftUI settings window. The delegate wires the action closures.
final class AppModel: ObservableObject {
    @Published var nowPlaying = "Starting…"
    @Published var isLoggedIn = false
    @Published var launchAtLogin = false
    @Published var showMenuBarIcon = true
    @Published var showDockIcon = true
    @Published var bakeInMissionControl = false
    @Published var hideOverlayWhenIdle = false
    @Published var desktopFrameMode = DesktopFrameMode.always
    @Published var useVibrantColors = false
    @Published var mediaDisplayMode = MediaDisplayMode.canvasWhenAvailable
    @Published var songInfoVisibility = SongInfoVisibility.briefly
    @Published var songInfoPosition = SongInfoPosition.bottomLeft
    @Published var songInfoSize = SongInfoSize.standard
    @Published var clickToRevealSongInfo = false
    @Published var selectedSettingsPage = SettingsPage.display

    var loginAction: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setShowMenuBarIcon: (Bool) -> Void = { _ in }
    var setShowDockIcon: (Bool) -> Void = { _ in }
    var setBakeInMissionControl: (Bool) -> Void = { _ in }
    var setHideOverlayWhenIdle: (Bool) -> Void = { _ in }
    var setDesktopFrameMode: (DesktopFrameMode) -> Void = { _ in }
    var setUseVibrantColors: (Bool) -> Void = { _ in }
    var setMediaDisplayMode: (MediaDisplayMode) -> Void = { _ in }
    var setSongInfoVisibility: (SongInfoVisibility) -> Void = { _ in }
    var setSongInfoPosition: (SongInfoPosition) -> Void = { _ in }
    var setSongInfoSize: (SongInfoSize) -> Void = { _ in }
    var setClickToRevealSongInfo: (Bool) -> Void = { _ in }
}
