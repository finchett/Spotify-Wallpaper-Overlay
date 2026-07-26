import AppKit
import SwiftUI
import ServiceManagement
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let spotify = SpotifyClient()
    private let overlay = OverlayController()
    private let canvas = CanvasClient()
    private let wallpaperBaker = WallpaperBaker()
    private let session = URLSession(configuration: .default)
    private var timer: Timer?
    private var pendingWallpaperBake: DispatchWorkItem?
    private var pendingIdleRetreat: DispatchWorkItem?
    private var signalSources: [DispatchSourceSignal] = []
    private var desktopClickMonitor: Any?
    private var isShuttingDown = false
    private var isPollInFlight = false
    private let artworkCache = NSCache<NSString, NSImage>()
    private var pendingCanvas: (trackID: String, url: URL)?

    // A lightweight state/id probe. Metadata, artwork and Canvas only load on change.
    private let pollInterval: TimeInterval = 0.5

    /// Track id currently shown, so we only reload media on change.
    private var currentTrackID: String?

    // Last shown state, so a screen reconfiguration can be re-pushed to fresh windows.
    private var lastTrack: NowPlaying?
    private var lastCover: NSImage?
    private var lastCanvasURL: URL?
    private var isIdle = false

    private let model = AppModel()
    private var loginController: SpotifyLoginController?
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var nowPlayingItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.isLoggedIn = Credentials.hasStoredCookie()
        model.launchAtLogin = (SMAppService.mainApp.status == .enabled)
        model.showMenuBarIcon = Settings.showMenuBarIcon
        model.showDockIcon = Settings.showDockIcon
        model.bakeInMissionControl = Settings.bakeInMissionControl
        model.hideOverlayWhenIdle = Settings.hideOverlayWhenIdle
        model.desktopFrameMode = Settings.desktopFrameMode
        model.useVibrantColors = Settings.useVibrantColors
        model.mediaDisplayMode = Settings.mediaDisplayMode
        model.songInfoVisibility = Settings.songInfoVisibility
        model.songInfoPosition = Settings.songInfoPosition
        model.songInfoSize = Settings.songInfoSize
        model.clickToRevealSongInfo = Settings.clickToRevealSongInfo
        model.loginAction = { [weak self] in self?.presentLogin() }
        model.setLaunchAtLogin = { [weak self] on in self?.applyLaunchAtLogin(on) }
        model.setShowMenuBarIcon = { [weak self] on in self?.applyMenuBarVisibility(on) }
        model.setShowDockIcon = { [weak self] on in self?.applyDockVisibility(on) }
        model.setBakeInMissionControl = { [weak self] on in
            self?.applyMissionControlBaking(on)
        }
        model.setHideOverlayWhenIdle = { [weak self] on in
            self?.applyHideOverlayWhenIdle(on)
        }
        model.setDesktopFrameMode = { [weak self] mode in
            self?.applyDesktopFrameMode(mode)
        }
        model.setUseVibrantColors = { [weak self] on in
            self?.applyUseVibrantColors(on)
        }
        model.setMediaDisplayMode = { [weak self] mode in
            self?.applyMediaDisplayMode(mode)
        }
        model.setSongInfoVisibility = { [weak self] visibility in
            self?.applySongInfoVisibility(visibility)
        }
        model.setSongInfoPosition = { [weak self] position in
            self?.applySongInfoPosition(position)
        }
        model.setSongInfoSize = { [weak self] size in
            self?.applySongInfoSize(size)
        }
        model.setClickToRevealSongInfo = { [weak self] on in
            self?.applyClickToRevealSongInfo(on)
        }

        setupMenuBar(enabled: model.showMenuBarIcon)
        // Show the window on launch only when there's a Dock icon; in background-agent mode
        // (Dock hidden, e.g. launched at login) stay quiet — reopen via the menu bar.
        if Settings.showDockIcon { showSettingsWindow() }

        overlay.setHideWhenIdle(model.hideOverlayWhenIdle)
        overlay.setDesktopFrameMode(model.desktopFrameMode)
        overlay.setUseVibrantColors(model.useVibrantColors)
        overlay.setSongInfoVisibility(model.songInfoVisibility)
        overlay.setSongInfoPosition(model.songInfoPosition)
        overlay.setSongInfoSize(model.songInfoSize)
        overlay.rebuildForScreens()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Re-assert the overlay on Space changes to reduce wallpaper flicker during the swipe.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillPowerOff),
            name: NSWorkspace.willPowerOffNotification, object: nil)

        installSignalHandlers()
        installDesktopClickMonitor()
        startPolling()
    }

    func applicationWillTerminate(_ notification: Notification) {
        restoreWallpaperBeforeExit()
    }

    private func restoreWallpaperBeforeExit() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        timer?.invalidate()
        pendingWallpaperBake?.cancel()
        pendingIdleRetreat?.cancel()
        if let desktopClickMonitor {
            NSEvent.removeMonitor(desktopClickMonitor)
            self.desktopClickMonitor = nil
        }
        wallpaperBaker.restore()
    }

    private func installSignalHandlers() {
        for number in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            Darwin.signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                self?.terminate(afterReceiving: number)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func terminate(afterReceiving number: Int32) {
        restoreWallpaperBeforeExit()
        Darwin.signal(number, SIG_DFL)
        Darwin.raise(number)
        Darwin._exit(128 + number)
    }

    @objc private func systemWillPowerOff() {
        restoreWallpaperBeforeExit()
    }

    // Keep running (as the desktop overlay) when the window closes; reopen via the dock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    // MARK: - Settings window

    private func showSettingsWindow() {
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Spotify Wallpaper"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        settingsWindow = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu bar (optional)

    private func setupMenuBar(enabled: Bool) {
        if enabled {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.image = NSImage(systemSymbolName: "music.note",
                                         accessibilityDescription: "Spotify Wallpaper")
            let menu = NSMenu()
            let nowPlaying = NSMenuItem(title: model.nowPlaying, action: nil, keyEquivalent: "")
            nowPlaying.isEnabled = false
            menu.addItem(nowPlaying)
            nowPlayingItem = nowPlaying
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Open Spotify Wallpaper", action: #selector(openSettings), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
            menu.items.forEach { $0.target = self }
            item.menu = menu
            statusItem = item
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            nowPlayingItem = nil
        }
    }

    private func applyMenuBarVisibility(_ on: Bool) {
        Settings.showMenuBarIcon = on
        model.showMenuBarIcon = on
        setupMenuBar(enabled: on)
    }

    private func applyDockVisibility(_ on: Bool) {
        Settings.showDockIcon = on
        model.showDockIcon = on
        NSApp.setActivationPolicy(on ? .regular : .accessory)
        if on { NSApp.activate(ignoringOtherApps: true) }
    }

    private func applyMissionControlBaking(_ on: Bool) {
        Settings.bakeInMissionControl = on
        model.bakeInMissionControl = on
        if on {
            scheduleWallpaperBake()
        } else {
            pendingWallpaperBake?.cancel()
            pendingWallpaperBake = nil
            pendingIdleRetreat?.cancel()
            pendingIdleRetreat = nil
            wallpaperBaker.restore()
            if isIdle {
                overlay.showIdle()
            }
        }
    }

    private func applyHideOverlayWhenIdle(_ on: Bool) {
        Settings.hideOverlayWhenIdle = on
        model.hideOverlayWhenIdle = on
        overlay.setHideWhenIdle(on)
    }

    private func applyDesktopFrameMode(_ mode: DesktopFrameMode) {
        Settings.desktopFrameMode = mode
        model.desktopFrameMode = mode
        overlay.setDesktopFrameMode(mode)
        scheduleWallpaperBake()
    }

    private func applyUseVibrantColors(_ on: Bool) {
        Settings.useVibrantColors = on
        model.useVibrantColors = on
        overlay.setUseVibrantColors(on)
        scheduleWallpaperBake()
    }

    private func applyMediaDisplayMode(_ mode: MediaDisplayMode) {
        Settings.mediaDisplayMode = mode
        model.mediaDisplayMode = mode
        guard !isIdle, let track = lastTrack, let cover = lastCover else { return }
        overlay.update(
            track: track,
            cover: cover,
            canvasURL: mode == .canvasWhenAvailable ? lastCanvasURL : nil)
        scheduleWallpaperBake()
    }

    private func applySongInfoVisibility(_ visibility: SongInfoVisibility) {
        Settings.songInfoVisibility = visibility
        model.songInfoVisibility = visibility
        overlay.setSongInfoVisibility(visibility)
    }

    private func applySongInfoPosition(_ position: SongInfoPosition) {
        Settings.songInfoPosition = position
        model.songInfoPosition = position
        overlay.setSongInfoPosition(position)
    }

    private func applySongInfoSize(_ size: SongInfoSize) {
        Settings.songInfoSize = size
        model.songInfoSize = size
        overlay.setSongInfoSize(size)
    }

    private func applyClickToRevealSongInfo(_ on: Bool) {
        Settings.clickToRevealSongInfo = on
        model.clickToRevealSongInfo = on
    }

    private func installDesktopClickMonitor() {
        desktopClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDown
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                guard let self,
                      self.model.clickToRevealSongInfo,
                      !self.isIdle,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier ==
                        "com.apple.finder",
                      !self.pointerIsInsideFinderWindow() else { return }
                self.overlay.revealSongInfo()
            }
        }
    }

    /// Finder owns both ordinary windows and the desktop. A desktop click brings Finder
    /// forward; excluding its layer-zero windows leaves the desktop and its icons.
    private func pointerIsInsideFinderWindow() -> Bool {
        let cocoaPoint = NSEvent.mouseLocation
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        let quartzPoint = CGPoint(
            x: cocoaPoint.x,
            y: mainHeight - cocoaPoint.y)
        guard let windows = CGWindowListCopyWindowInfo(
            .optionOnScreenOnly,
            kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { info in
            guard (info[kCGWindowOwnerName as String] as? String) == "Finder",
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer >= 0,
                  let boundsValue = info[kCGWindowBounds as String],
                  let bounds = CGRect(
                    dictionaryRepresentation: boundsValue as! CFDictionary)
            else { return false }
            return bounds.contains(quartzPoint)
        }
    }

    @objc private func openSettings() { showSettingsWindow() }

    // MARK: - Launch at login

    private func applyLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nThis needs the app to be signed and in /Applications."
            alert.runModal()
        }
        model.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    // MARK: - Login

    private func presentLogin() {
        let controller = SpotifyLoginController()
        loginController = controller   // retain while the window is open
        controller.present { [weak self] success in
            guard let self else { return }
            self.loginController = nil
            self.model.isLoggedIn = Credentials.hasStoredCookie()
            guard success else { return }
            self.canvas.resetToken()   // re-authenticate with the new cookie
            self.currentTrackID = nil  // force the current track to reload its Canvas
            self.poll()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    @objc private func refreshNow() {
        currentTrackID = nil   // force a reload even if the same track is playing
        poll()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func screensChanged() {
        pendingWallpaperBake?.cancel()
        overlay.rebuildForScreens()
        if isIdle {
            overlay.showIdle()
        } else if let track = lastTrack, let cover = lastCover {
            overlay.update(
                track: track,
                cover: cover,
                canvasURL: model.mediaDisplayMode == .canvasWhenAvailable
                    ? lastCanvasURL : nil)
            scheduleWallpaperBake()
        }
    }

    @objc private func activeSpaceChanged() {
        overlay.reassert()
    }

    private func setStatus(_ text: String) {
        model.nowPlaying = text
        nowPlayingItem?.title = text
    }

    /// Wallpaper changes are tied to playback/content changes, never Mission Control.
    /// The short delay lets the overlay finish its reveal before it is snapshotted.
    private func scheduleWallpaperBake() {
        pendingWallpaperBake?.cancel()
        guard model.bakeInMissionControl, !isIdle else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.model.bakeInMissionControl,
                  !self.isIdle else { return }
            self.wallpaperBaker.bake(self.overlay.snapshots())
            self.pendingWallpaperBake = nil
        }
        pendingWallpaperBake = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Restore while the full overlay still covers the desktop, allow WallpaperAgent
    /// half a second to settle, then reveal the already-restored wallpaper.
    private func beginIdleTransition() {
        pendingIdleRetreat?.cancel()
        pendingIdleRetreat = nil

        let wasBaked = wallpaperBaker.isBaked
        if model.bakeInMissionControl {
            wallpaperBaker.restore()
        }

        guard model.bakeInMissionControl, wasBaked else {
            overlay.showIdle()
            return
        }

        guard model.hideOverlayWhenIdle else {
            overlay.showIdle()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isIdle else { return }
            self.overlay.showIdle()
            self.pendingIdleRetreat = nil
        }
        pendingIdleRetreat = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func poll() {
        guard !isPollInFlight, !isShuttingDown else { return }
        isPollInFlight = true
        spotify.probe { [weak self] result in
            guard let self else { return }
            self.isPollInFlight = false
            switch result {
            case .playing(let trackID):
                self.handlePlaying(trackID: trackID)
            case .stopped:
                self.handleStopped()
            case .unavailable:
                // A transient AppleScript failure is not a playback stop.
                break
            }
        }
    }

    private func handleStopped() {
        setStatus("Spotify not playing")
        if !isIdle {
            isIdle = true
            currentTrackID = nil     // so playback resumes with a fresh reveal
            pendingCanvas = nil
            pendingWallpaperBake?.cancel()
            pendingWallpaperBake = nil
            beginIdleTransition()
        }
    }

    private func handlePlaying(trackID: String) {
        pendingIdleRetreat?.cancel()
        pendingIdleRetreat = nil
        isIdle = false

        guard trackID != currentTrackID else { return }
        currentTrackID = trackID
        pendingCanvas = nil

        // Resuming the same track should not wait for metadata or artwork again.
        if let track = lastTrack, track.id == trackID, let cover = lastCover {
            setStatus("\(track.title) — \(track.artist)")
            overlay.update(
                track: track,
                cover: cover,
                canvasURL: model.mediaDisplayMode == .canvasWhenAvailable
                    ? lastCanvasURL : nil)
            scheduleWallpaperBake()
            return
        }

        spotify.fetchMetadata { [weak self] np in
            guard let self else { return }
            guard let np, np.id == trackID else {
                if self.currentTrackID == trackID {
                    self.currentTrackID = nil
                }
                return
            }
            guard self.currentTrackID == trackID else { return }
            self.setStatus("\(np.title) — \(np.artist)")
            self.loadMedia(for: np)
        }
    }

    private func loadMedia(for np: NowPlaying) {
        guard let art = URL(string: np.artworkURL) else {
            currentTrackID = nil
            return
        }

        if let cover = artworkCache.object(forKey: np.id as NSString) {
            show(track: np, cover: cover)
        } else {
            session.dataTask(with: art) { [weak self] data, _, _ in
                guard let self, let data, let cover = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    guard np.id == self.currentTrackID else { return }
                    self.artworkCache.setObject(cover, forKey: np.id as NSString)
                    self.show(track: np, cover: cover)
                }
            }.resume()
        }

        canvas.fetchCanvasURL(trackURI: np.id) { [weak self] canvasURL in
            guard let self, let canvasURL else { return }
            DispatchQueue.main.async {
                guard np.id == self.currentTrackID else { return }
                self.pendingCanvas = (np.id, canvasURL)
                guard self.lastTrack?.id == np.id, let cover = self.lastCover else { return }
                self.lastCanvasURL = canvasURL
                guard self.model.mediaDisplayMode == .canvasWhenAvailable else {
                    return
                }
                self.overlay.update(track: np, cover: cover, canvasURL: canvasURL)
            }
        }
    }

    private func show(track: NowPlaying, cover: NSImage) {
        guard track.id == currentTrackID else { return }
        let canvasURL = pendingCanvas?.trackID == track.id ? pendingCanvas?.url : nil
        lastTrack = track
        lastCover = cover
        lastCanvasURL = canvasURL
        overlay.update(
            track: track,
            cover: cover,
            canvasURL: model.mediaDisplayMode == .canvasWhenAvailable
                ? canvasURL : nil)
        scheduleWallpaperBake()
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        }
    }
}
