import AppKit

/// Owns one desktop-level overlay window per screen and fans updates out to them.
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var hideWhenIdle = false
    private var hideFrameWhenIdle = false
    private var showDesktopFrame = true
    private var useVibrantColors = false
    private var songInfoVisibility = SongInfoVisibility.briefly
    private var songInfoPosition = SongInfoPosition.bottomLeft
    private var songInfoSize = SongInfoSize.standard
    private var isIdle = true

    /// (Re)create a window for every current screen. Safe to call on hot-plug / resolution change.
    func rebuildForScreens() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { OverlayWindow(screen: $0) }
        windows.forEach {
            $0.overlayView.setHideWhenIdle(
                hideWhenIdle, currentlyIdle: isIdle, animated: false)
            $0.overlayView.setHideFrameWhenIdle(
                hideFrameWhenIdle, currentlyIdle: isIdle, animated: false)
            $0.overlayView.setShowDesktopFrame(showDesktopFrame)
            $0.overlayView.setUseVibrantColors(useVibrantColors)
            $0.overlayView.setSongInfoVisibility(songInfoVisibility)
            $0.overlayView.setSongInfoPosition(songInfoPosition)
            $0.overlayView.setSongInfoSize(songInfoSize)
        }
        windows.forEach { $0.orderFrontRegardless() }
    }

    func update(track: NowPlaying, cover: NSImage, canvasURL: URL?) {
        isIdle = false
        for window in windows {
            window.overlayView.update(track: track, cover: cover, canvasURL: canvasURL)
        }
    }

    /// Nothing playing — reveal the real wallpaper, optionally hiding the whole overlay.
    func showIdle() {
        isIdle = true
        for window in windows {
            window.overlayView.showIdle()
        }
    }

    func setHideWhenIdle(_ enabled: Bool) {
        hideWhenIdle = enabled
        for window in windows {
            window.overlayView.setHideWhenIdle(
                enabled, currentlyIdle: isIdle, animated: true)
        }
    }

    func setHideFrameWhenIdle(_ enabled: Bool) {
        hideFrameWhenIdle = enabled
        for window in windows {
            window.overlayView.setHideFrameWhenIdle(
                enabled, currentlyIdle: isIdle, animated: true)
        }
    }

    func setShowDesktopFrame(_ enabled: Bool) {
        showDesktopFrame = enabled
        windows.forEach { $0.overlayView.setShowDesktopFrame(enabled) }
    }

    func setUseVibrantColors(_ enabled: Bool) {
        useVibrantColors = enabled
        for window in windows {
            window.overlayView.setUseVibrantColors(enabled)
        }
    }

    func setSongInfoVisibility(_ visibility: SongInfoVisibility) {
        songInfoVisibility = visibility
        windows.forEach { $0.overlayView.setSongInfoVisibility(visibility) }
    }

    func setSongInfoPosition(_ position: SongInfoPosition) {
        songInfoPosition = position
        windows.forEach { $0.overlayView.setSongInfoPosition(position) }
    }

    func setSongInfoSize(_ size: SongInfoSize) {
        songInfoSize = size
        windows.forEach { $0.overlayView.setSongInfoSize(size) }
    }

    func revealSongInfo() {
        windows.forEach { $0.overlayView.revealSongInfo() }
    }

    /// Re-assert the windows (e.g. on a Space change) to reduce transition flicker.
    func reassert() {
        windows.forEach { $0.orderFrontRegardless() }
    }

    func snapshots() -> [(screen: NSScreen, image: NSImage)] {
        windows.compactMap { window in
            guard let image = window.snapshot() else { return nil }
            return (window.wallpaperScreen, image)
        }
    }
}
