import AppKit

/// A borderless, click-through window pinned just above the wallpaper and below every
/// app window. Joins all Spaces, so a single window covers the whole desktop everywhere.
/// The real desktop wallpaper for one screen, with the placement macOS draws it with.
struct CapturedWallpaper {
    let image: NSImage
    let gravity: CALayerContentsGravity
    let fillColor: NSColor?

    init(image: NSImage, options: [NSWorkspace.DesktopImageOptionKey: Any]) {
        self.image = image
        fillColor = options[.fillColor] as? NSColor
        let scaling = (options[.imageScaling] as? NSNumber)
            .flatMap { NSImageScaling(rawValue: $0.uintValue) } ??
            .scaleProportionallyUpOrDown
        let allowsClipping = (options[.allowClipping] as? Bool) ?? true
        switch scaling {
        case .scaleAxesIndependently:
            gravity = .resize
        case .scaleNone:
            gravity = .center
        case .scaleProportionallyDown:
            gravity = .resizeAspect
        default:
            gravity = allowsClipping ? .resizeAspectFill : .resizeAspect
        }
    }
}

final class OverlayWindow: NSWindow {
    let overlayView: OverlayContentView
    let wallpaperScreen: NSScreen
    let isPrimaryDisplay: Bool
    /// A copy of the real wallpaper beneath the overlay. It stands in while
    /// WallpaperAgent restarts after a bake, and lives outside overlayView because the
    /// idle animation can mask and hide that view's entire layer tree.
    private let standInLayer = CALayer()

    init(screen: NSScreen, isPrimaryDisplay: Bool) {
        wallpaperScreen = screen
        self.isPrimaryDisplay = isPrimaryDisplay
        overlayView = OverlayContentView(
            screen: screen,
            isPrimaryDisplay: isPrimaryDisplay)
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

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.wantsLayer = true
        standInLayer.frame = container.bounds
        standInLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        standInLayer.isHidden = true
        container.layer?.addSublayer(standInLayer)
        overlayView.frame = container.bounds
        overlayView.autoresizingMask = [.width, .height]
        container.addSubview(overlayView)
        contentView = container
    }

    func showWallpaperStandIn(_ wallpaper: CapturedWallpaper) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        standInLayer.removeAllAnimations()
        standInLayer.contents = wallpaper.image.cgImage(
            forProposedRect: nil, context: nil, hints: nil)
        standInLayer.contentsGravity = wallpaper.gravity
        standInLayer.backgroundColor = wallpaper.fillColor?.cgColor
        standInLayer.opacity = 1
        standInLayer.isHidden = false
        CATransaction.commit()
    }

    func hideWallpaperStandIn() {
        guard !standInLayer.isHidden else { return }
        // A short fade softens any mismatch, e.g. a dynamic wallpaper's current frame.
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setCompletionBlock { [standInLayer] in
            guard standInLayer.opacity == 0 else { return }
            standInLayer.isHidden = true
            standInLayer.contents = nil
        }
        standInLayer.opacity = 0
        CATransaction.commit()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func snapshot() -> NSImage? {
        guard overlayView.hasVisibleContent else { return nil }
        return overlayView.wallpaperSnapshot()
    }
}
