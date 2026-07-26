import SwiftUI
import AppKit

/// A compact preferences window with persistent navigation and a live desktop preview.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            settingsDetail
            Divider()
            DesktopPreview(model: model)
        }
        .frame(width: 930, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                Text("Spotify Wallpaper")
                    .font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            ForEach(SettingsPage.allCases) { page in
                SidebarButton(
                    title: page.title,
                    systemImage: page.systemImage,
                    isSelected: model.selectedSettingsPage == page
                ) {
                    model.selectedSettingsPage = page
                }
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 178)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    @ViewBuilder
    private var settingsDetail: some View {
        switch model.selectedSettingsPage {
        case .display:
            displaySettings
        case .background:
            backgroundSettings
        case .songInfo:
            songInfoSettings
        case .playback:
            playbackSettings
        case .missionControl:
            missionControlSettings
        case .app:
            appSettings
        }
    }

    private var displaySettings: some View {
        SettingsPanel(
            title: "Display",
            subtitle: "Choose what appears at the center of your desktop.",
            systemImage: "rectangle.on.rectangle") {
            VStack(spacing: 13) {
                SettingChoice(
                    title: "Main artwork",
                    description: "Canvas falls back to album artwork when a video is unavailable.",
                    selection: Binding(
                        get: { model.mediaDisplayMode },
                        set: { model.setMediaDisplayMode($0) }),
                    choices: [
                        ("Canvas when available", .canvasWhenAvailable),
                        ("Album artwork only", .artworkOnly),
                    ])
                Divider()
                SettingChoice(
                    title: "Black desktop frame",
                    description: "Controls the black top strip and rounded corner masks.",
                    selection: Binding(
                        get: { model.desktopFrameMode },
                        set: { model.setDesktopFrameMode($0) }),
                    choices: [
                        ("Always", .always),
                        ("Never", .never),
                        ("When a song is playing", .whenPlaying),
                    ])
            }
        }
    }

    private var backgroundSettings: some View {
        SettingsPanel(
            title: "Background",
            subtitle: "Choose what sits behind the main artwork.",
            systemImage: "photo") {
            VStack(spacing: 13) {
                SettingChoice(
                    title: "Source",
                    description: "Use album colors, your current wallpaper, or a separate image.",
                    selection: Binding(
                        get: { model.backgroundMode },
                        set: { model.setBackgroundMode($0) }),
                    choices: [
                        ("Album colors", .albumColors),
                        ("Current wallpaper", .desktopWallpaper),
                        ("Chosen image", .customImage),
                    ])

                if model.backgroundMode == .albumColors {
                    Divider()
                    SettingToggle(
                        title: "Boost album colors",
                        description: "Makes artwork backgrounds brighter and more saturated.",
                        isOn: Binding(
                            get: { model.useVibrantColors },
                            set: { model.setUseVibrantColors($0) }))
                } else {
                    if model.backgroundMode == .customImage {
                        Divider()
                        SettingAction(
                            title: "Chosen image",
                            description: model.customBackgroundImageName ??
                                "No image selected",
                            buttonTitle: "Choose…",
                            action: model.chooseBackgroundImageAction)
                    }
                    Divider()
                    SettingSlider(
                        title: "Blur",
                        description: "Softens the background behind the artwork.",
                        valueText: "\(Int(model.backgroundBlur.rounded()))",
                        value: Binding(
                            get: { model.backgroundBlur },
                            set: { model.setBackgroundBlur($0) }),
                        range: 0...30)
                    Divider()
                    SettingSlider(
                        title: "Brightness",
                        description: "Darken or brighten the background image.",
                        valueText:
                            "\(Int((model.backgroundBrightness * 100).rounded()))%",
                        value: Binding(
                            get: { model.backgroundBrightness },
                            set: { model.setBackgroundBrightness($0) }),
                        range: -0.8...0.5)
                }
            }
        }
    }

    private var songInfoSettings: some View {
        SettingsPanel(
            title: "Song Info",
            subtitle: "Control when and where the title and artist appear.",
            systemImage: "textformat") {
            VStack(spacing: 13) {
                SettingChoice(
                    title: "Visibility",
                    description: "Briefly shows it after play, pause, or a song change.",
                    selection: Binding(
                        get: { model.songInfoVisibility },
                        set: { model.setSongInfoVisibility($0) }),
                    choices: [
                        ("Briefly", .briefly),
                        ("Always", .always),
                        ("Never", .never),
                    ])
                Divider()
                SettingChoice(
                    title: "Position",
                    description: "Places the title and artist around the main display.",
                    selection: Binding(
                        get: { model.songInfoPosition },
                        set: { model.setSongInfoPosition($0) }),
                    choices: [
                        ("Bottom left", .bottomLeft),
                        ("Bottom right", .bottomRight),
                        ("Top left", .topLeft),
                        ("Top right", .topRight),
                        ("Center", .center),
                    ])
                Divider()
                SettingChoice(
                    title: "Text size",
                    description: "Adjusts both the song title and artist.",
                    selection: Binding(
                        get: { model.songInfoSize },
                        set: { model.setSongInfoSize($0) }),
                    choices: [
                        ("Small", .small),
                        ("Standard", .standard),
                        ("Large", .large),
                    ])
                Divider()
                SettingToggle(
                    title: "Reveal when desktop is clicked",
                    description: "Shows song info briefly without consuming the click.",
                    isOn: Binding(
                        get: { model.clickToRevealSongInfo },
                        set: { model.setClickToRevealSongInfo($0) }),
                    isEnabled: model.songInfoVisibility != .always)
            }
        }
    }

    private var playbackSettings: some View {
        SettingsPanel(
            title: "When Playback Stops",
            subtitle: "Choose what remains visible while Spotify is idle.",
            systemImage: "stop.circle") {
            SettingToggle(
                title: "Hide the now-playing artwork",
                description: "Slides the artwork away until playback resumes.",
                isOn: Binding(
                    get: { model.hideOverlayWhenIdle },
                    set: { model.setHideOverlayWhenIdle($0) }))
        }
    }

    private var missionControlSettings: some View {
        SettingsPanel(
            title: "Wallpaper",
            subtitle: "Optional help for macOS Space and Mission Control visual glitches.",
            systemImage: "rectangle.3.group") {
            SettingToggle(
                title: "Temporarily use the overlay as your wallpaper",
                description: "Helps prevent flicker when switching Spaces or using Mission Control. We do our best to restore your original wallpaper whenever playback stops or the app quits.",
                isOn: Binding(
                    get: { model.bakeInMissionControl },
                    set: { model.setBakeInMissionControl($0) }))
        }
    }

    private var appSettings: some View {
        SettingsPanel(
            title: "App",
            subtitle: "Choose how Spotify Wallpaper runs on your Mac.",
            systemImage: "gearshape") {
            VStack(spacing: 13) {
                SpotifyConnectionRow(model: model)
                Divider()
                SettingToggle(
                    title: "Open automatically at login",
                    description: "Starts Spotify Wallpaper when you sign in to your Mac.",
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }))
                Divider()
                SettingToggle(
                    title: "Keep an icon in the menu bar",
                    description: "Quick access to settings, refresh, and quit.",
                    isOn: Binding(
                        get: { model.showMenuBarIcon },
                        set: { model.setShowMenuBarIcon($0) }))
                Divider()
                SettingToggle(
                    title: "Show the app in the Dock",
                    description: "Keeps the app in the Dock and opens settings at launch.",
                    isOn: Binding(
                        get: { model.showDockIcon },
                        set: { model.setShowDockIcon($0) }))
            }
        }
    }
}

private extension SettingsPage {
    var systemImage: String {
        switch self {
        case .display: return "rectangle.on.rectangle"
        case .background: return "photo"
        case .songInfo: return "textformat"
        case .playback: return "stop.circle"
        case .missionControl: return "rectangle.3.group"
        case .app: return "gearshape"
        }
    }
}

private struct SidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 19))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            Card {
                content
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 392, alignment: .top)
    }
}

private struct SpotifyConnectionRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Spotify connection")
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isLoggedIn ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(model.isLoggedIn
                         ? "Connected — Canvas videos enabled"
                         : "Connect to enable Canvas videos")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(model.isLoggedIn ? "Reconnect…" : "Connect…") {
                model.loginAction()
            }
        }
    }
}

private struct SettingToggle: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    var isEnabled = true
    var isNested = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.leading, isNested ? 16 : 0)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
    }
}

private struct SettingChoice<Value: Hashable>: View {
    let title: String
    let description: String
    @Binding var selection: Value
    let choices: [(String, Value)]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            Picker("", selection: $selection) {
                ForEach(choices.indices, id: \.self) { index in
                    Text(choices[index].0).tag(choices[index].1)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 154)
        }
    }
}

private struct SettingAction: View {
    let title: String
    let description: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            Button(buttonTitle, action: action)
        }
    }
}

private struct SettingSlider: View {
    let title: String
    let description: String
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(valueText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}

private struct DesktopPreview: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Desktop Preview")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(previewStateLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.10), in: Capsule())
            }

            desktop
                .aspectRatio(16 / 10, contentMode: .fit)

            Text(previewCaption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(24)
        .frame(width: 359)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.30))
    }

    private var isStoppedPreview: Bool {
        model.selectedSettingsPage == .playback
    }

    private var frameVisible: Bool {
        switch model.desktopFrameMode {
        case .always:
            return true
        case .never:
            return false
        case .whenPlaying:
            return !isStoppedPreview
        }
    }

    private var previewStateLabel: String {
        isStoppedPreview ? "STOPPED" : "PLAYING"
    }

    private var previewCaption: String {
        switch model.selectedSettingsPage {
        case .display:
            switch model.desktopFrameMode {
            case .always:
                return "The black top strip and rounded corners remain at all times."
            case .never:
                return "The black top strip and rounded corner masks are disabled."
            case .whenPlaying:
                return "The black frame appears during playback and hides when Spotify stops."
            }
        case .background:
            switch model.backgroundMode {
            case .albumColors:
                return "The background follows the current album artwork."
            case .desktopWallpaper:
                return "Your current desktop wallpaper sits behind the artwork."
            case .customImage:
                return model.customBackgroundImage == nil
                    ? "Choose an image to use behind the artwork."
                    : "Your chosen image sits behind the artwork."
            }
        case .songInfo:
            return model.songInfoVisibility == .never
                ? "Song information is hidden."
                : "The sample title shows the selected position and text size."
        case .playback:
            switch model.desktopFrameMode {
            case .always:
                return "The black desktop frame remains after the artwork retreats."
            case .whenPlaying:
                return "The artwork and black desktop frame retreat together."
            case .never:
                return "The black desktop frame is disabled."
            }
        case .missionControl:
            return model.bakeInMissionControl
                ? "The app temporarily uses this composition as each Space's wallpaper."
                : "The wallpaper workaround is off; only the live overlay is used."
        case .app:
            return "App controls do not change the desktop composition."
        }
    }

    private var desktop: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                previewBackground

                if !isStoppedPreview {
                    mediaCard(in: size)
                    if model.songInfoVisibility != .never {
                        songInfo(in: size)
                    }
                }

                if frameVisible {
                    VStack(spacing: 0) {
                        Color.black.frame(height: max(13, size.height * 0.075))
                        Spacer()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.black.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        }
    }

    @ViewBuilder
    private var previewBackground: some View {
        if isStoppedPreview {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.22, blue: 0.38),
                    Color(red: 0.04, green: 0.08, blue: 0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
        } else {
            switch model.backgroundMode {
            case .albumColors:
                if model.useVibrantColors {
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.18, blue: 0.48),
                            Color(red: 0.15, green: 0.08, blue: 0.30),
                        ],
                        startPoint: .top,
                        endPoint: .bottom)
                } else {
                    LinearGradient(
                        colors: [
                            Color(red: 0.34, green: 0.20, blue: 0.31),
                            Color(red: 0.10, green: 0.07, blue: 0.13),
                        ],
                        startPoint: .top,
                        endPoint: .bottom)
                }
            case .desktopWallpaper:
                imageBackground(model.desktopBackgroundPreview)
            case .customImage:
                imageBackground(model.customBackgroundImage)
            }
        }
    }

    @ViewBuilder
    private func imageBackground(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(1 + model.backgroundBlur / 300)
                .blur(radius: model.backgroundBlur * 0.18)
                .brightness(model.backgroundBrightness)
                .clipped()
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.22, blue: 0.32),
                        Color(red: 0.05, green: 0.08, blue: 0.13),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)
                Image(systemName: "photo")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    private func mediaCard(in size: CGSize) -> some View {
        let canvas = model.mediaDisplayMode == .canvasWhenAvailable
        let cardWidth = canvas ? size.width * 0.20 : size.width * 0.27
        let cardHeight = canvas ? cardWidth * 1.72 : cardWidth

        return ZStack {
            LinearGradient(
                colors: canvas
                    ? [Color.pink, Color.purple, Color.indigo]
                    : [Color.orange, Color.pink, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)
            Image(systemName: canvas ? "video.fill" : "music.note")
                .font(.system(size: canvas ? 18 : 22, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
    }

    private func songInfo(in size: CGSize) -> some View {
        let scale: CGFloat
        switch model.songInfoSize {
        case .small: scale = 0.75
        case .standard: scale = 1.0
        case .large: scale = 1.30
        }

        return VStack(
            alignment: textHorizontalAlignment,
            spacing: 1
        ) {
            Text("Midnight Drive")
                .font(.system(size: 12 * scale, weight: .bold))
                .lineLimit(1)
            Text("The Satellites")
                .font(.system(size: 9 * scale, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.55), radius: 3, y: 1)
        .frame(maxWidth: size.width * 0.42, alignment: textFrameAlignment)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: songInfoAlignment)
        .padding(songInfoPadding(in: size))
    }

    private var textHorizontalAlignment: HorizontalAlignment {
        switch model.songInfoPosition {
        case .bottomRight, .topRight: return .trailing
        case .center: return .center
        default: return .leading
        }
    }

    private var textFrameAlignment: Alignment {
        switch model.songInfoPosition {
        case .bottomRight, .topRight: return .trailing
        case .center: return .center
        default: return .leading
        }
    }

    private var songInfoAlignment: Alignment {
        switch model.songInfoPosition {
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .center: return .center
        }
    }

    private func songInfoPadding(in size: CGSize) -> EdgeInsets {
        let side = size.width * 0.045
        let bottom = size.height * 0.055
        let top = size.height * 0.13
        switch model.songInfoPosition {
        case .bottomLeft:
            return EdgeInsets(top: 0, leading: side, bottom: bottom, trailing: 0)
        case .bottomRight:
            return EdgeInsets(top: 0, leading: 0, bottom: bottom, trailing: side)
        case .topLeft:
            return EdgeInsets(top: top, leading: side, bottom: 0, trailing: 0)
        case .topRight:
            return EdgeInsets(top: top, leading: 0, bottom: 0, trailing: side)
        case .center:
            return EdgeInsets()
        }
    }
}

/// A rounded, subtly-bordered container used for a group of related controls.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.primary.opacity(0.06)))
    }
}
