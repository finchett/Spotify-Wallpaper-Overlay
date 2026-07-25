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
    private var isShuttingDown = false

    // Poll cadence in seconds. Cheap AppleScript query; media only loads on change.
    private let pollInterval: TimeInterval = 3.0

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
        model.hideFrameWhenIdle = Settings.hideFrameWhenIdle
        model.useVibrantColors = Settings.useVibrantColors
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
        model.setHideFrameWhenIdle = { [weak self] on in
            self?.applyHideFrameWhenIdle(on)
        }
        model.setUseVibrantColors = { [weak self] on in
            self?.applyUseVibrantColors(on)
        }

        setupMenuBar(enabled: model.showMenuBarIcon)
        // Show the window on launch only when there's a Dock icon; in background-agent mode
        // (Dock hidden, e.g. launched at login) stay quiet — reopen via the menu bar.
        if Settings.showDockIcon { showSettingsWindow() }

        overlay.setHideWhenIdle(model.hideOverlayWhenIdle)
        overlay.setHideFrameWhenIdle(model.hideFrameWhenIdle)
        overlay.setUseVibrantColors(model.useVibrantColors)
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

    private func applyHideFrameWhenIdle(_ on: Bool) {
        Settings.hideFrameWhenIdle = on
        model.hideFrameWhenIdle = on
        overlay.setHideFrameWhenIdle(on)
    }

    private func applyUseVibrantColors(_ on: Bool) {
        Settings.useVibrantColors = on
        model.useVibrantColors = on
        overlay.setUseVibrantColors(on)
        scheduleWallpaperBake()
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
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
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
            overlay.update(track: track, cover: cover, canvasURL: lastCanvasURL)
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
        guard let np = spotify.fetch() else {
            setStatus("Spotify not playing")
            if !isIdle {
                isIdle = true
                currentTrackID = nil     // so playback resumes with a fresh reveal
                pendingWallpaperBake?.cancel()
                pendingWallpaperBake = nil
                beginIdleTransition()
            }
            return
        }
        pendingIdleRetreat?.cancel()
        pendingIdleRetreat = nil
        isIdle = false
        setStatus("\(np.title) — \(np.artist)")

        guard np.id != currentTrackID, let art = URL(string: np.artworkURL) else { return }
        currentTrackID = np.id

        // 1) Download the static cover and show it immediately (fallback look).
        session.dataTask(with: art) { [weak self] data, _, _ in
            guard let self, let data, let cover = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard np.id == self.currentTrackID else { return }   // track moved on
                self.lastTrack = np
                self.lastCover = cover
                self.lastCanvasURL = nil
                self.overlay.update(track: np, cover: cover, canvasURL: nil)
                self.scheduleWallpaperBake()
            }
        }.resume()

        // 2) In parallel, try the (unofficial) Spotify Canvas. If it resolves and the
        //    track is still current, upgrade the overlay to the looping video.
        canvas.fetchCanvasURL(trackURI: np.id) { [weak self] canvasURL in
            guard let self, let canvasURL else { return }
            DispatchQueue.main.async {
                guard np.id == self.currentTrackID, let cover = self.lastCover else { return }
                self.lastCanvasURL = canvasURL
                self.overlay.update(track: np, cover: cover, canvasURL: canvasURL)
            }
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        }
    }
}
