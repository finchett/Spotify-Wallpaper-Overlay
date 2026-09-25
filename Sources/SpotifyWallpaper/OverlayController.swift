import AppKit

/// Owns one desktop-level overlay window per screen and fans updates out to them.
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var hideWhenIdle = false
    private var desktopFrameMode = DesktopFrameMode.always
    private var showDesktopFrameOnSecondaryDisplays = false
    private var useVibrantColors = false
    private var songInfoVisibility = SongInfoVisibility.briefly
    private var songInfoPosition = SongInfoPosition.bottomLeft
    private var songInfoSize = SongInfoSize.standard
    private var backgroundMode = OverlayBackgroundMode.albumColors
    private var backgroundBlur = 0.0
    private var backgroundBrightness = 0.0
    private var customBackgroundImage: NSImage?
    private var desktopBackgrounds: [String: CapturedWallpaper] = [:]
    private var isIdle = true
    private var mainBarAdjustment = 0.0
    private var secondaryBarAdjustment = 0.0
    private var secondaryCornerRadius = Settings.maxSecondaryCornerRadius
    /// Identifies our own baked images, which must never be captured as the wallpaper.
    var isBakedWallpaper: (URL) -> Bool = { _ in false }

    /// (Re)create a window for every current screen. Safe to call on hot-plug / resolution change.
    func rebuildForScreens() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.enumerated().map { index, screen in
            OverlayWindow(screen: screen, isPrimaryDisplay: index == 0)
        }
        captureDesktopWallpapers(overwrite: false)
        windows.forEach {
            $0.overlayView.setHideWhenIdle(
                hideWhenIdle, currentlyIdle: isIdle, animated: false)
            applyDesktopFrameMode(to: $0)
            applyFrameGeometry(to: $0)
            $0.overlayView.setUseVibrantColors(useVibrantColors)
            $0.overlayView.setSongInfoVisibility(songInfoVisibility)
            $0.overlayView.setSongInfoPosition(songInfoPosition)
            $0.overlayView.setSongInfoSize(songInfoSize)
            applyBackground(to: $0)
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

    func setDesktopFrameMode(_ mode: DesktopFrameMode) {
        desktopFrameMode = mode
        windows.forEach(applyDesktopFrameMode)
    }

    func setDesktopFrameOnSecondaryDisplays(_ enabled: Bool) {
        showDesktopFrameOnSecondaryDisplays = enabled
        windows.forEach(applyDesktopFrameMode)
    }

    func setFrameGeometry(
        mainBarAdjustment: Double,
        secondaryBarAdjustment: Double,
        secondaryCornerRadius: Double
    ) {
        self.mainBarAdjustment = mainBarAdjustment
        self.secondaryBarAdjustment = secondaryBarAdjustment
        self.secondaryCornerRadius = secondaryCornerRadius
        windows.forEach(applyFrameGeometry)
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

    func setBackgroundMode(_ mode: OverlayBackgroundMode) {
        backgroundMode = mode
        windows.forEach(applyBackground)
    }

    func setCustomBackgroundImage(_ image: NSImage?) {
        customBackgroundImage = image
        guard backgroundMode == .customImage else { return }
        windows.forEach(applyBackground)
    }

    func setBackgroundEffects(blur: Double, brightness: Double) {
        backgroundBlur = blur
        backgroundBrightness = brightness
        guard backgroundMode != .albumColors else { return }
        windows.forEach(applyBackground)
    }

    func refreshDesktopWallpapers() {
        captureDesktopWallpapers(overwrite: true)
        guard backgroundMode == .desktopWallpaper else { return }
        windows.forEach(applyBackground)
    }

    private func applyBackground(to window: OverlayWindow) {
        let image: NSImage?
        switch backgroundMode {
        case .albumColors:
            image = nil
        case .desktopWallpaper:
            image = desktopBackgrounds[screenKey(window.wallpaperScreen)]?.image
        case .customImage:
            image = customBackgroundImage
        }
        window.overlayView.setBackground(
            mode: backgroundMode,
            image: image,
            blur: backgroundBlur,
            brightness: backgroundBrightness)
    }

    private func applyDesktopFrameMode(to window: OverlayWindow) {
        let enabledOnDisplay =
            window.isPrimaryDisplay ||
            showDesktopFrameOnSecondaryDisplays
        window.overlayView.setDesktopFrameMode(
            enabledOnDisplay ? desktopFrameMode : .never)
    }

    private func applyFrameGeometry(to window: OverlayWindow) {
        window.overlayView.setFrameGeometry(
            barAdjustmentPixels: CGFloat(
                window.isPrimaryDisplay ? mainBarAdjustment : secondaryBarAdjustment),
            secondaryCornerRadius: CGFloat(secondaryCornerRadius))
    }

    private func captureDesktopWallpapers(overwrite: Bool) {
        for window in windows {
            let screen = window.wallpaperScreen
            let key = screenKey(screen)
            if !overwrite, desktopBackgrounds[key] != nil {
                continue
            }
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  !isBakedWallpaper(url),
                  let image = NSImage(contentsOf: url) else {
                continue
            }
            desktopBackgrounds[key] = CapturedWallpaper(
                image: image,
                options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
        }
    }

    private func screenKey(_ screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.stringValue ??
            screen.localizedName
    }

    /// Covers every screen with its captured real wallpaper, beneath the overlay, so the
    /// idle animation can reveal it before WallpaperAgent has redrawn. Shows nothing and
    /// returns false unless every screen has a capture.
    func showWallpaperStandIns() -> Bool {
        let captures = windows.map { desktopBackgrounds[screenKey($0.wallpaperScreen)] }
        guard !windows.isEmpty, !captures.contains(where: { $0 == nil }) else {
            return false
        }
        for (window, capture) in zip(windows, captures) {
            window.showWallpaperStandIn(capture!)
        }
        return true
    }

    func hideWallpaperStandIns() {
        windows.forEach { $0.hideWallpaperStandIn() }
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
