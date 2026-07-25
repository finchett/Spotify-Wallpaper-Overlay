import Combine

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
    @Published var hideFrameWhenIdle = false
    @Published var useVibrantColors = false

    var loginAction: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setShowMenuBarIcon: (Bool) -> Void = { _ in }
    var setShowDockIcon: (Bool) -> Void = { _ in }
    var setBakeInMissionControl: (Bool) -> Void = { _ in }
    var setHideOverlayWhenIdle: (Bool) -> Void = { _ in }
    var setHideFrameWhenIdle: (Bool) -> Void = { _ in }
    var setUseVibrantColors: (Bool) -> Void = { _ in }
}
