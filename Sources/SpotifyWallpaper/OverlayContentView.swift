import AppKit
import AVFoundation
import CoreImage
import CoreVideo

/// The layered view that fills a screen. The layout is identical either way — vibrant
/// gradient background, a centered rounded card, title/artist bottom-left — the only
/// difference is what fills the card:
///   • Canvas mode  — the looping Canvas video.
///   • Cover mode   — the static cover with a slow Ken Burns zoom.
/// Both are topped with the black menu-bar bar and black rounded corners.
final class OverlayContentView: NSView {
    // Geometry is captured per display. External displays can have a different
    // menu-bar height (or no reserved menu-bar area at all).
    private let menuBarHeight: CGFloat
    private let cornerRadius: CGFloat

    /// Holds all the now-playing content (gradient, card, text) so it can be revealed or
    /// hidden as a group — leaving the black bar + corners always visible on top.
    private let contentLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private let backgroundImageLayer = CALayer()
    private let cardShadowLayer = CALayer()
    private let cardLayer = CALayer()
    private let playerLayer = AVPlayerLayer()
    private let titleLayer = CATextLayer()
    private let artistLayer = CATextLayer()
    private let barLayer = CALayer()
    private let cornerLayer = CAShapeLayer()

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var videoOutputItem: AVPlayerItem?
    private var videoOutputObserver: Any?
    private var playerReadyObservation: NSKeyValueObservation?
    private var canvasRevealNotBefore: CFTimeInterval = 0
    private let videoFrameContext = CIContext()

    /// Card aspect ratio (width / height): 1 for the square cover, the video's ratio for Canvas.
    private var cardAspect: CGFloat = 1.0

    /// The track currently shown, so we only play the reveal animation on a genuinely new one.
    private var shownTrackID: String?
    private var hideWhenIdle = false
    private var desktopFrameMode = DesktopFrameMode.always
    private var useVibrantColors = false
    private var songInfoVisibility = SongInfoVisibility.briefly
    private var songInfoPosition = SongInfoPosition.bottomLeft
    private var songInfoSize = SongInfoSize.standard
    private var backgroundMode = OverlayBackgroundMode.albumColors
    private var backgroundBlur: CGFloat = 0
    private var backgroundBrightness: CGFloat = 0
    private var isIdle = true
    private var visibilityGeneration = 0
    private var textHideWorkItem: DispatchWorkItem?
    private var currentBaseColor: NSColor?

    var hasVisibleContent: Bool { !contentLayer.isHidden }

    private var scale: CGFloat { window?.backingScaleFactor ?? 2 }

    init(screen: NSScreen) {
        let visibleTopInset = max(
            0,
            screen.frame.maxY - screen.visibleFrame.maxY)
        menuBarHeight = max(
            visibleTopInset,
            screen.safeAreaInsets.top)
        cornerRadius = 44 / max(screen.backingScaleFactor, 1)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setupLayers()
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Renders the wallpaper version of the overlay. Text is intentionally omitted, and
    /// AVPlayerLayer is replaced with its current decoded frame because AppKit's display
    /// cache does not reliably composite hardware-backed video layers.
    func wallpaperSnapshot() -> NSImage? {
        layoutSubtreeIfNeeded()
        displayIfNeeded()

        let rect = bounds
        guard !rect.isEmpty else { return nil }

        let savedTitleHidden = titleLayer.isHidden
        let savedArtistHidden = artistLayer.isHidden
        let savedCardHidden = cardLayer.isHidden
        let savedPlayerHidden = playerLayer.isHidden
        let savedCardContents = cardLayer.contents

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleLayer.isHidden = true
        artistLayer.isHidden = true
        if player != nil {
            if let videoFrame = currentVideoFrame() {
                cardLayer.contents = videoFrame
            }
            cardLayer.isHidden = false
            playerLayer.isHidden = true
        }
        CATransaction.commit()

        defer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            titleLayer.isHidden = savedTitleHidden
            artistLayer.isHidden = savedArtistHidden
            cardLayer.isHidden = savedCardHidden
            playerLayer.isHidden = savedPlayerHidden
            cardLayer.contents = savedCardContents
            CATransaction.commit()
        }

        guard let rep = bitmapImageRepForCachingDisplay(in: rect) else {
            return nil
        }
        cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    override var isFlipped: Bool { false }   // bottom-left origin, matching the layout math

    // MARK: - Layer tree

    private func setupLayers() {
        guard let root = layer else { return }

        // Now-playing content, grouped so we can reveal/hide it without touching the overlays.
        root.addSublayer(contentLayer)
        contentLayer.isHidden = true   // start empty; the wallpaper shows through until playback

        gradientLayer.startPoint = CGPoint(x: 0.5, y: 1)   // top
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)     // bottom
        contentLayer.addSublayer(gradientLayer)

        backgroundImageLayer.contentsGravity = .resizeAspectFill
        backgroundImageLayer.masksToBounds = true
        backgroundImageLayer.isHidden = true
        contentLayer.addSublayer(backgroundImageLayer)

        cardShadowLayer.backgroundColor = NSColor.white.cgColor   // shadow caster behind the card
        cardShadowLayer.shadowColor = NSColor.black.cgColor
        cardShadowLayer.shadowOpacity = 0.45
        contentLayer.addSublayer(cardShadowLayer)

        cardLayer.contentsGravity = .resizeAspectFill
        cardLayer.masksToBounds = true
        contentLayer.addSublayer(cardLayer)

        // The Canvas video fills the same card slot as the cover, clipped to its corners.
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.masksToBounds = true
        playerLayer.isHidden = true
        contentLayer.addSublayer(playerLayer)

        configureText(titleLayer, color: NSColor.white)
        configureText(artistLayer, color: NSColor(white: 1, alpha: 0.65))
        contentLayer.addSublayer(titleLayer)
        contentLayer.addSublayer(artistLayer)

        // Always-on overlays, above the content, so they persist even when idle.
        barLayer.backgroundColor = NSColor.black.cgColor
        root.addSublayer(barLayer)

        cornerLayer.fillRule = .evenOdd
        cornerLayer.fillColor = NSColor.black.cgColor
        root.addSublayer(cornerLayer)
    }

    private func configureText(_ layer: CATextLayer, color: NSColor) {
        layer.foregroundColor = color.cgColor
        layer.alignmentMode = .left
        layer.truncationMode = .end
        layer.isWrapped = false
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: -1)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let b = bounds
        let s = scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        contentLayer.frame = b
        gradientLayer.frame = b
        let backgroundBleed = backgroundBlur * 2
        backgroundImageLayer.frame = b.insetBy(
            dx: -backgroundBleed,
            dy: -backgroundBleed)
        backgroundImageLayer.contentsScale = s

        // Black menu-bar bar across the top.
        let barHeight = menuBarHeight
        barLayer.frame = CGRect(x: 0, y: b.height - barHeight, width: b.width, height: barHeight)

        // Black rounded corners on the content region *below* the bar.
        let radius = cornerRadius
        let contentRect = CGRect(x: 0, y: 0, width: b.width, height: b.height - barHeight)
        let path = CGMutablePath()
        path.addRect(contentRect)
        path.addRoundedRect(in: contentRect, cornerWidth: radius, cornerHeight: radius)
        cornerLayer.path = path
        cornerLayer.frame = b

        // Centered card, sized to the media's aspect ratio inside a bounding box
        // (square for the cover, portrait for a Canvas video).
        let maxH = b.height * 0.5
        let maxW = b.width * 0.42
        var cardW = min(maxW, maxH * cardAspect)
        var cardH = cardW / cardAspect
        if cardH > maxH { cardH = maxH; cardW = cardH * cardAspect }
        let cardRect = CGRect(x: (b.width - cardW) / 2,
                              y: (b.height - cardH) / 2 + b.height * 0.02,
                              width: cardW, height: cardH)
        let minSide = min(cardW, cardH)
        for card in [cardShadowLayer, cardLayer, playerLayer] {
            card.frame = cardRect
            card.cornerRadius = minSide * 0.03
            card.contentsScale = s
        }
        cardShadowLayer.shadowRadius = minSide * 0.06
        cardShadowLayer.shadowOffset = CGSize(width: 0, height: -minSide * 0.02)

        // Title + artist, positioned and scaled according to the user's display choices.
        let margin = b.width * 0.045
        let sizeScale: CGFloat
        switch songInfoSize {
        case .small: sizeScale = 0.70
        case .standard: sizeScale = 1.0
        case .large: sizeScale = 1.30
        }
        let titleSize = max(15, b.height * 0.032 * sizeScale)
        let artistSize = max(11, b.height * 0.020 * sizeScale)
        let titleHeight = titleSize * 1.4
        let artistHeight = artistSize * 1.4
        let gap = artistSize * 0.2
        let blockHeight = titleHeight + gap + artistHeight
        let contentTop = b.height - barHeight

        let textWidth: CGFloat
        let textX: CGFloat
        let artistY: CGFloat
        let alignment: CATextLayerAlignmentMode
        switch songInfoPosition {
        case .bottomLeft:
            textWidth = b.width * 0.46
            textX = margin
            artistY = b.height * 0.06
            alignment = .left
        case .bottomRight:
            textWidth = b.width * 0.46
            textX = b.width - margin - textWidth
            artistY = b.height * 0.06
            alignment = .right
        case .topLeft:
            textWidth = b.width * 0.46
            textX = margin
            artistY = contentTop - margin - blockHeight
            alignment = .left
        case .topRight:
            textWidth = b.width * 0.46
            textX = b.width - margin - textWidth
            artistY = contentTop - margin - blockHeight
            alignment = .right
        case .center:
            textWidth = b.width * 0.80
            textX = b.width * 0.10
            artistY = (contentTop - blockHeight) / 2
            alignment = .center
        }

        applyFont(titleLayer, size: titleSize, weight: .bold, scale: s)
        applyFont(artistLayer, size: artistSize, weight: .medium, scale: s)
        titleLayer.alignmentMode = alignment
        artistLayer.alignmentMode = alignment
        artistLayer.frame = CGRect(
            x: textX, y: artistY, width: textWidth, height: artistHeight)
        titleLayer.frame = CGRect(
            x: textX,
            y: artistY + artistHeight + gap,
            width: textWidth,
            height: titleHeight)
    }

    private func applyFont(_ layer: CATextLayer, size: CGFloat, weight: NSFont.Weight, scale: CGFloat) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        layer.font = font
        layer.fontSize = size
        layer.contentsScale = scale
    }

    // MARK: - Content updates

    func update(track: NowPlaying, cover: NSImage, canvasURL: URL?) {
        let wasIdle = isIdle
        let isNewTrack = track.id != shownTrackID
        let revealWholeOverlay =
            hideWhenIdle && desktopFrameMode == .whenPlaying &&
            (wasIdle || layer?.isHidden == true)
        isIdle = false
        layer?.isHidden = false
        applyFrameVisibility()

        // A Canvas URL arrives as a second update for the same track. It must not cancel
        // a reveal or slide that the cover update has already started.
        if wasIdle || isNewTrack || contentLayer.isHidden {
            visibilityGeneration += 1
            layer?.mask = nil
            contentLayer.mask = nil
        }

        let wasHidden = contentLayer.isHidden || (wasIdle && hideWhenIdle)
        let shouldSlide = !wasHidden && isNewTrack
        // Preserve the complete old scene underneath the incoming one.
        let outgoing = shouldSlide ? snapshotScene() : nil

        let base = ColorExtractor.vibrant(from: cover)
        currentBaseColor = base

        // Scene swaps must be instantaneous. The page-slide animation below supplies
        // all motion; Core Animation's default contents/colors fades cause ghosting.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let cg = cover.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil) {
            cardLayer.contents = cg
        }
        applyGradient(from: base)
        titleLayer.string = track.title
        artistLayer.string = track.artist
        CATransaction.commit()

        canvasRevealNotBefore =
            CACurrentMediaTime() + (shouldSlide ? 0.62 : 0)
        if let canvasURL {
            startCanvas(url: canvasURL)
        } else {
            stopCanvas()
        }
        startAmbientAnimations()
        layoutSubtreeIfNeeded()

        shownTrackID = track.id
        contentLayer.isHidden = false
        if wasIdle || isNewTrack {
            applySongInfoVisibility()
        }
        // First appearance / resuming from idle gets the circular fill; a song switch
        // slides old→off and new→in; a Canvas upgrade of the same track gets nothing.
        if revealWholeOverlay {
            animateReveal(masking: layer)
        } else if wasHidden {
            animateReveal(masking: contentLayer)
        } else if let outgoing {
            performSlideIn(over: outgoing)
        }
    }

    /// Duplicates the complete outgoing scene so the new one can slide over it.
    private func snapshotScene() -> CALayer {
        let container = CALayer()
        container.frame = contentLayer.bounds

        if backgroundImageLayer.isHidden {
            let source =
                (gradientLayer.presentation() as? CAGradientLayer) ??
                gradientLayer
            let background = CAGradientLayer()
            copyPresentationGeometry(
                from: gradientLayer,
                to: background)
            background.colors = source.colors
            background.locations = source.locations
            background.startPoint = source.startPoint
            background.endPoint = source.endPoint
            container.addSublayer(background)
        } else {
            let source = backgroundImageLayer.presentation() ??
                backgroundImageLayer
            let background = CALayer()
            copyPresentationGeometry(
                from: backgroundImageLayer,
                to: background)
            background.contents = source.contents
            background.contentsGravity =
                backgroundImageLayer.contentsGravity
            background.masksToBounds =
                backgroundImageLayer.masksToBounds
            background.filters = backgroundImageLayer.filters
            container.addSublayer(background)
        }

        let shadow = CALayer()
        let shadowSource = cardShadowLayer.presentation() ??
            cardShadowLayer
        copyPresentationGeometry(
            from: cardShadowLayer,
            to: shadow)
        shadow.cornerRadius = shadowSource.cornerRadius
        shadow.backgroundColor = shadowSource.backgroundColor
        shadow.shadowColor = shadowSource.shadowColor
        shadow.shadowOpacity = shadowSource.shadowOpacity
        shadow.shadowRadius = shadowSource.shadowRadius
        shadow.shadowOffset = shadowSource.shadowOffset
        container.addSublayer(shadow)

        // Freeze the exact outgoing media. This prevents a playing Canvas from briefly
        // reverting to its cover while the old scene moves away.
        let visibleMediaLayer =
            playerLayer.isHidden ? cardLayer : playerLayer
        let media = CALayer()
        let mediaSource = visibleMediaLayer.presentation() ??
            visibleMediaLayer
        copyPresentationGeometry(
            from: visibleMediaLayer,
            to: media)
        if !playerLayer.isHidden, let frame = currentVideoFrame() {
            media.contents = frame
        } else {
            media.contents = cardLayer.contents
        }
        media.contentsGravity = visibleMediaLayer.contentsGravity
        media.cornerRadius = mediaSource.cornerRadius
        media.masksToBounds = true
        container.addSublayer(media)

        for src in [titleLayer, artistLayer] {
            let presented = (src.presentation() as? CATextLayer) ??
                src
            let text = CATextLayer()
            copyPresentationGeometry(from: src, to: text)
            text.string = src.string
            text.font = src.font
            text.fontSize = src.fontSize
            text.foregroundColor = src.foregroundColor
            text.alignmentMode = src.alignmentMode
            text.truncationMode = src.truncationMode
            text.isWrapped = src.isWrapped
            text.contentsScale = src.contentsScale
            text.opacity = presented.opacity
            container.addSublayer(text)
        }

        // The real layers are the incoming scene, so the snapshot belongs underneath.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.insertSublayer(container, below: gradientLayer)
        CATransaction.commit()
        return container
    }

    private func copyPresentationGeometry(
        from source: CALayer,
        to destination: CALayer
    ) {
        let presented = source.presentation() ?? source
        destination.bounds = presented.bounds
        destination.position = presented.position
        destination.anchorPoint = presented.anchorPoint
        destination.transform = presented.transform
        destination.opacity = presented.opacity
    }

    /// The new scene enters as an opaque page over the previous scene. The previous scene
    /// shifts only slightly left underneath it, while incoming elements travel at different
    /// depths. Nothing cross-fades.
    private func performSlideIn(over outgoing: CALayer) {
        let dx = bounds.width
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let duration: CFTimeInterval = 0.60

        CATransaction.begin()
        CATransaction.setCompletionBlock { outgoing.removeFromSuperlayer() }
        let outgoingShift = CABasicAnimation(keyPath: "position.x")
        outgoingShift.fromValue = 0
        outgoingShift.toValue = -dx * 0.22
        outgoingShift.isAdditive = true
        outgoingShift.duration = duration
        outgoingShift.timingFunction = ease
        outgoing.add(outgoingShift, forKey: "parallax-underlay")

        // The opaque background is the leading page. The foreground trails it by
        // different amounts, producing depth while remaining part of the same entrance.
        for background in [gradientLayer, backgroundImageLayer] {
            let backgroundSlide = CABasicAnimation(
                keyPath: "position.x")
            backgroundSlide.fromValue = dx
            backgroundSlide.toValue = 0
            backgroundSlide.isAdditive = true
            backgroundSlide.duration = duration
            backgroundSlide.timingFunction = ease
            background.add(
                backgroundSlide,
                forKey: "incoming-background")
        }

        let incomingLayers: [(CALayer, CGFloat)] = [
            (cardShadowLayer, 1.08),
            (cardLayer, 1.10),
            (playerLayer, 1.10),
            (titleLayer, 1.18),
            (artistLayer, 1.15),
        ]
        for (foreground, depth) in incomingLayers {
            let incoming = CABasicAnimation(keyPath: "position.x")
            incoming.fromValue = dx * depth
            incoming.toValue = 0
            incoming.isAdditive = true
            incoming.duration = duration
            incoming.timingFunction = ease
            foreground.add(incoming, forKey: "parallax-slidein")
        }
        CATransaction.commit()
    }

    private func showTextTemporarily() {
        textHideWorkItem?.cancel()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleLayer.opacity = 1
        artistLayer.opacity = 1
        CATransaction.commit()
        titleLayer.removeAnimation(forKey: "delayed-text-fade")
        artistLayer.removeAnimation(forKey: "delayed-text-fade")

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isIdle else { return }
            for textLayer in [self.titleLayer, self.artistLayer] {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                textLayer.opacity = 0
                CATransaction.commit()

                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                fade.duration = 0.65
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                textLayer.add(fade, forKey: "delayed-text-fade")
            }
            self.textHideWorkItem = nil
        }
        textHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func applySongInfoVisibility() {
        textHideWorkItem?.cancel()
        textHideWorkItem = nil
        titleLayer.removeAnimation(forKey: "delayed-text-fade")
        artistLayer.removeAnimation(forKey: "delayed-text-fade")

        switch songInfoVisibility {
        case .briefly:
            showTextTemporarily()
        case .always:
            setTextOpacity(1)
        case .never:
            setTextOpacity(0)
        }
    }

    private func setTextOpacity(_ opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleLayer.opacity = opacity
        artistLayer.opacity = opacity
        CATransaction.commit()
    }

    func setSongInfoVisibility(_ visibility: SongInfoVisibility) {
        songInfoVisibility = visibility
        guard !isIdle else { return }
        applySongInfoVisibility()
    }

    func setSongInfoPosition(_ position: SongInfoPosition) {
        songInfoPosition = position
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func setSongInfoSize(_ size: SongInfoSize) {
        songInfoSize = size
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func revealSongInfo() {
        guard !isIdle, songInfoVisibility != .always else { return }
        showTextTemporarily()
    }

    /// Nothing playing: either retreat the whole overlay into the bottom-left corner or
    /// hide only the content and leave the black bar + corners visible.
    func showIdle() {
        isIdle = true
        visibilityGeneration += 1
        textHideWorkItem?.cancel()
        textHideWorkItem = nil
        contentLayer.mask = nil
        shownTrackID = nil
        if hideWhenIdle {
            hideIdleLayers(animated: true)
        } else {
            contentLayer.isHidden = true
            stopCanvas()
            applyFrameVisibility()
        }
    }

    func setHideWhenIdle(
        _ enabled: Bool,
        currentlyIdle: Bool,
        animated: Bool
    ) {
        hideWhenIdle = enabled
        isIdle = currentlyIdle
        visibilityGeneration += 1

        guard currentlyIdle else {
            layer?.isHidden = false
            layer?.mask = nil
            contentLayer.mask = nil
            applyFrameVisibility()
            return
        }

        if enabled {
            hideIdleLayers(animated: animated)
        } else {
            layer?.mask = nil
            layer?.isHidden = false
            contentLayer.isHidden = true
            stopCanvas()
            applyFrameVisibility()
        }
    }

    func setDesktopFrameMode(_ mode: DesktopFrameMode) {
        desktopFrameMode = mode
        visibilityGeneration += 1
        layer?.mask = nil
        contentLayer.mask = nil
        layer?.isHidden = false
        applyFrameVisibility()
    }

    private func applyFrameVisibility() {
        let visible: Bool
        switch desktopFrameMode {
        case .always:
            visible = true
        case .never:
            visible = false
        case .whenPlaying:
            visible = !isIdle
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayer.isHidden = !visible
        cornerLayer.isHidden = !visible
        CATransaction.commit()
    }

    func setUseVibrantColors(_ enabled: Bool) {
        useVibrantColors = enabled
        guard let currentBaseColor else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyGradient(from: currentBaseColor)
        CATransaction.commit()
    }

    func setBackground(
        mode: OverlayBackgroundMode,
        image: NSImage?,
        blur: Double,
        brightness: Double
    ) {
        backgroundMode = mode
        backgroundBlur = CGFloat(max(0, blur))
        backgroundBrightness = CGFloat(
            min(0.5, max(-0.8, brightness)))
        backgroundImageLayer.contents = image?.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil)
        applyBackgroundPresentation()
        needsLayout = true
    }

    private func applyBackgroundPresentation() {
        let useImage =
            backgroundMode != .albumColors &&
            backgroundImageLayer.contents != nil
        gradientLayer.isHidden = useImage
        backgroundImageLayer.isHidden = !useImage

        guard useImage else {
            backgroundImageLayer.filters = nil
            return
        }

        var filters: [CIFilter] = []
        if backgroundBlur > 0,
           let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setDefaults()
            blur.setValue(backgroundBlur, forKey: kCIInputRadiusKey)
            filters.append(blur)
        }
        if abs(backgroundBrightness) > 0.001,
           let color = CIFilter(name: "CIColorControls") {
            color.setDefaults()
            color.setValue(
                backgroundBrightness,
                forKey: kCIInputBrightnessKey)
            filters.append(color)
        }
        backgroundImageLayer.filters = filters
    }

    private func hideIdleLayers(animated: Bool) {
        guard let root = layer else { return }
        root.isHidden = false

        let hidesWholeOverlay = desktopFrameMode == .whenPlaying
        if !hidesWholeOverlay {
            applyFrameVisibility()
        }
        let target = hidesWholeOverlay ? root : contentLayer
        if animated, !target.isHidden {
            animateRetreat(
                masking: target,
                hidesWholeOverlay: hidesWholeOverlay)
        } else {
            target.mask = nil
            contentLayer.isHidden = true
            root.isHidden = hidesWholeOverlay
        }
    }

    /// Reveals a layer with a circular wipe growing from the bottom-left corner.
    private func animateReveal(masking target: CALayer?) {
        guard let target else { return }
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }

        let radius = hypot(w, h) * 1.1                 // reaches past the far corner
        let corner = CGPoint(x: 0, y: 0)               // bottom-left (non-flipped)
        let endRect = CGRect(x: corner.x - radius, y: corner.y - radius, width: radius * 2, height: radius * 2)
        let startRect = CGRect(origin: corner, size: .zero)

        let mask = CAShapeLayer()
        mask.path = CGPath(ellipseIn: endRect, transform: nil)
        target.mask = mask

        let reveal = CABasicAnimation(keyPath: "path")
        reveal.fromValue = CGPath(ellipseIn: startRect, transform: nil)
        reveal.toValue = CGPath(ellipseIn: endRect, transform: nil)
        reveal.duration = 0.9
        reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let generation = visibilityGeneration
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak target] in
            guard let self,
                  self.visibilityGeneration == generation else { return }
            target?.mask = nil
        }
        mask.add(reveal, forKey: "reveal")
        CATransaction.commit()
    }

    /// Runs the reveal path backwards for either the content or the entire composition.
    private func animateRetreat(
        masking target: CALayer,
        hidesWholeOverlay: Bool
    ) {
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else {
            contentLayer.isHidden = true
            target.isHidden = true
            stopCanvas()
            return
        }

        let generation = visibilityGeneration
        let radius = hypot(w, h) * 1.1
        let corner = CGPoint(x: 0, y: 0)
        let fullRect = CGRect(
            x: corner.x - radius,
            y: corner.y - radius,
            width: radius * 2,
            height: radius * 2)
        let pointRect = CGRect(origin: corner, size: .zero)

        target.isHidden = false
        let mask = CAShapeLayer()
        mask.path = CGPath(ellipseIn: pointRect, transform: nil)
        target.mask = mask

        let retreat = CABasicAnimation(keyPath: "path")
        retreat.fromValue = CGPath(ellipseIn: fullRect, transform: nil)
        retreat.toValue = CGPath(ellipseIn: pointRect, transform: nil)
        retreat.duration = 0.9
        retreat.timingFunction = CAMediaTimingFunction(name: .easeIn)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak target] in
            guard let self,
                  let target,
                  self.visibilityGeneration == generation,
                  self.isIdle,
                  self.hideWhenIdle,
                  (self.desktopFrameMode == .whenPlaying) ==
                    hidesWholeOverlay else { return }
            target.mask = nil
            self.contentLayer.isHidden = true
            target.isHidden = true
            self.stopCanvas()
        }
        mask.add(retreat, forKey: "retreat")
        CATransaction.commit()
    }

    // MARK: - Canvas video

    private func startCanvas(url: URL) {
        // Fully detach the previous player first so AVPlayerLayer cannot retain and
        // ghost its last decoded frame into the incoming scene.
        let revealDeadline = canvasRevealNotBefore
        stopCanvas()
        canvasRevealNotBefore = revealDeadline

        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)   // seamless loop
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String:
                Int(kCVPixelFormatType_32BGRA),
        ])
        videoOutput = output
        attachVideoOutput(to: queue.currentItem)
        videoOutputObserver = queue.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self, weak queue] _ in
            self?.attachVideoOutput(to: queue?.currentItem)
        }
        player = queue

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.player = queue
        playerLayer.isHidden = true
        cardLayer.isHidden = false
        CATransaction.commit()

        playerReadyObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self, weak queue] layer, _ in
            guard layer.isReadyForDisplay else { return }
            let delay = max(
                0,
                (self?.canvasRevealNotBefore ?? 0) -
                    CACurrentMediaTime())
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let self,
                      let queue,
                      self.player === queue else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.playerLayer.isHidden = false
                self.cardLayer.isHidden = true
                CATransaction.commit()
                self.playerReadyObservation?.invalidate()
                self.playerReadyObservation = nil
            }
        }
        queue.play()

        // Canvas clips are portrait; assume 9:16 immediately, then refine to the real size.
        updateCardAspect(9.0 / 16.0)
        loadVideoAspect(url: url)
    }

    private func stopCanvas() {
        canvasRevealNotBefore = 0
        playerReadyObservation?.invalidate()
        playerReadyObservation = nil
        if let videoOutputObserver, let player {
            player.removeTimeObserver(videoOutputObserver)
        }
        videoOutputObserver = nil
        if let videoOutput, let videoOutputItem {
            videoOutputItem.remove(videoOutput)
        }
        videoOutputItem = nil
        videoOutput = nil

        player?.pause()
        player = nil
        looper = nil

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.player = nil
        playerLayer.isHidden = true
        cardLayer.isHidden = false
        CATransaction.commit()
        updateCardAspect(1.0)          // square for the cover
    }

    private func attachVideoOutput(to item: AVPlayerItem?) {
        guard let item, let videoOutput else { return }
        if videoOutputItem === item { return }
        if let videoOutputItem {
            videoOutputItem.remove(videoOutput)
        }
        item.add(videoOutput)
        videoOutputItem = item
    }

    private func currentVideoFrame() -> CGImage? {
        guard let player, let videoOutput else { return nil }
        let hostTime = CACurrentMediaTime()
        let outputTime = videoOutput.itemTime(forHostTime: hostTime)
        var displayTime = CMTime.invalid
        let pixelBuffer =
            videoOutput.copyPixelBuffer(
                forItemTime: outputTime,
                itemTimeForDisplay: &displayTime) ??
            videoOutput.copyPixelBuffer(
                forItemTime: player.currentTime(),
                itemTimeForDisplay: &displayTime)
        guard let pixelBuffer else { return nil }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        return videoFrameContext.createCGImage(image, from: image.extent)
    }

    /// Reads the video's true display size (accounting for any rotation) and matches the card to it.
    private func loadVideoAspect(url: URL) {
        let asset = AVURLAsset(url: url)
        Task { [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let naturalSize = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform) else { return }
            let oriented = naturalSize.applying(transform)
            let size = CGSize(width: abs(oriented.width), height: abs(oriented.height))
            guard size.width > 0, size.height > 0 else { return }
            await MainActor.run { self?.updateCardAspect(size.width / size.height) }
        }
    }

    private func updateCardAspect(_ aspect: CGFloat) {
        guard aspect > 0, abs(aspect - cardAspect) > 0.001 else { return }
        cardAspect = aspect
        needsLayout = true
    }

    // MARK: - Ambient motion

    private func startAmbientAnimations() {
        // Slow Ken Burns zoom on the cover card (cover mode).
        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 1.0
        zoom.toValue = 1.08
        zoom.duration = 24
        zoom.autoreverses = true
        zoom.repeatCount = .infinity
        zoom.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cardLayer.removeAnimation(forKey: "kenburns")
        cardLayer.add(zoom, forKey: "kenburns")

        // Drifting gradient.
        let drift = CABasicAnimation(keyPath: "startPoint")
        drift.fromValue = CGPoint(x: 0.3, y: 1.0)
        drift.toValue = CGPoint(x: 0.7, y: 1.0)
        drift.duration = 18
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradientLayer.removeAnimation(forKey: "drift")
        gradientLayer.add(drift, forKey: "drift")
    }

    private func adjust(_ color: NSColor, brightness: CGFloat, saturationScale: CGFloat) -> NSColor {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(deviceHue: h, saturation: min(1, s * saturationScale), brightness: brightness, alpha: 1)
    }

    private func applyGradient(from base: NSColor) {
        if useVibrantColors {
            gradientLayer.colors = [
                adjust(base, brightness: 0.70, saturationScale: 1.35).cgColor,
                adjust(base, brightness: 0.30, saturationScale: 1.15).cgColor,
            ]
        } else {
            gradientLayer.colors = [
                adjust(base, brightness: 0.42, saturationScale: 0.90).cgColor,
                adjust(base, brightness: 0.20, saturationScale: 0.95).cgColor,
            ]
        }
    }

}
