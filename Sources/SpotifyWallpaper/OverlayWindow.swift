import AppKit

/// A borderless, click-through window pinned just above the wallpaper and below every
/// app window. Joins all Spaces, so a single window covers the whole desktop everywhere.
final class OverlayWindow: NSWindow {
    let overlayView = OverlayContentView()
    let wallpaperScreen: NSScreen

    init(screen: NSScreen) {
        wallpaperScreen = screen
        super.init(contentRect: screen.frame,
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        setFrame(screen.frame, display: true)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true        // clicks fall through to the desktop / icons

        // Sit at the desktop level: above the wallpaper, below icons and all app windows.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // Show on every Space, don't move with Spaces, stay out of Mission Control cycling.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        contentView = overlayView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func snapshot() -> NSImage? {
        guard overlayView.hasVisibleContent else { return nil }
        overlayView.layoutSubtreeIfNeeded()
        overlayView.displayIfNeeded()
        let rect = overlayView.bounds
        guard !rect.isEmpty,
              let rep = overlayView.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        overlayView.cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }
}
