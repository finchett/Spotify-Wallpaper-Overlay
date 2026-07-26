import SwiftUI
import AppKit

/// The app's main window: a compact, native-feeling control panel.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                nowPlayingCard
                accountCard
                appearanceSection
                idleSection
                missionControlSection
                appSection
            }
            .padding(24)
        }
        .frame(width: 440, height: 760)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("Spotify Wallpaper")
                    .font(.system(size: 19, weight: .semibold))
                Text("Your desktop, now playing")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var nowPlayingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("NOW PLAYING", systemImage: "waveform")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(model.nowPlaying)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var accountCard: some View {
        Card {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
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
                .controlSize(.large)
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", systemImage: "paintpalette") {
            SettingToggle(
                title: "Boost album colors",
                description: "Makes artwork backgrounds brighter and more saturated.",
                isOn: Binding(
                    get: { model.useVibrantColors },
                    set: { model.setUseVibrantColors($0) }))
        }
    }

    private var idleSection: some View {
        SettingsSection(title: "When Playback Stops", systemImage: "stop.circle") {
            VStack(spacing: 13) {
                SettingToggle(
                    title: "Hide the now-playing artwork",
                    description: "Slides the artwork away until playback resumes.",
                    isOn: Binding(
                        get: { model.hideOverlayWhenIdle },
                        set: { model.setHideOverlayWhenIdle($0) }))
                Divider()
                SettingToggle(
                    title: "Hide the desktop frame too",
                    description: "Also hides the black top strip and rounded corners.",
                    isOn: Binding(
                        get: { model.hideFrameWhenIdle },
                        set: { model.setHideFrameWhenIdle($0) }),
                    isEnabled: model.hideOverlayWhenIdle,
                    isNested: true)
            }
        }
    }

    private var missionControlSection: some View {
        SettingsSection(title: "Mission Control", systemImage: "rectangle.3.group") {
            SettingToggle(
                title: "Keep artwork visible in Mission Control",
                description: "Temporarily applies the current artwork to every Space. Your original wallpaper is restored when playback stops or the app quits.",
                isOn: Binding(
                    get: { model.bakeInMissionControl },
                    set: { model.setBakeInMissionControl($0) }))
        }
    }

    private var appSection: some View {
        SettingsSection(title: "App", systemImage: "gearshape") {
            VStack(spacing: 13) {
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
                    title: "Show Spotify Wallpaper in the Dock",
                    description: "Keeps the app in the Dock and opens this window at launch.",
                    isOn: Binding(
                        get: { model.showDockIcon },
                        set: { model.setShowDockIcon($0) }))
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Card {
                content
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
        .padding(.leading, isNested ? 18 : 0)
        .opacity(isEnabled ? 1 : 0.45)
        .disabled(!isEnabled)
    }
}

/// A rounded, subtly-bordered container used for each settings section.
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
