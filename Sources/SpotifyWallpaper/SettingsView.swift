import SwiftUI
import AppKit

/// The app's main window: a compact, native-feeling control panel.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            nowPlayingCard
            accountCard
            optionsCard
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 400, height: 690)
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Spotify Account").font(.system(size: 13, weight: .medium))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(model.isLoggedIn ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(model.isLoggedIn ? "Connected" : "Not connected")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(model.isLoggedIn ? "Update…" : "Log In…") { model.loginAction() }
                    .controlSize(.large)
            }
        }
    }

    private var optionsCard: some View {
        Card {
            VStack(spacing: 12) {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }))
                Divider()
                Toggle("Show menu bar icon", isOn: Binding(
                    get: { model.showMenuBarIcon },
                    set: { model.setShowMenuBarIcon($0) }))
                Divider()
                Toggle("Show Dock icon", isOn: Binding(
                    get: { model.showDockIcon },
                    set: { model.setShowDockIcon($0) }))
                Divider()
                Toggle("Bake overlay during playback", isOn: Binding(
                    get: { model.bakeInMissionControl },
                    set: { model.setBakeInMissionControl($0) }))
                Divider()
                Toggle("Use vibrant colors", isOn: Binding(
                    get: { model.useVibrantColors },
                    set: { model.setUseVibrantColors($0) }))
                Divider()
                Toggle("Hide overlay when nothing is playing", isOn: Binding(
                    get: { model.hideOverlayWhenIdle },
                    set: { model.setHideOverlayWhenIdle($0) }))
                Divider()
                Toggle("Hide black strip and corners too", isOn: Binding(
                    get: { model.hideFrameWhenIdle },
                    set: { model.setHideFrameWhenIdle($0) }))
                    .padding(.leading, 20)
                    .disabled(!model.hideOverlayWhenIdle)
            }
            .toggleStyle(.switch)
            .font(.system(size: 13))
        }
    }
}

/// A rounded, subtly-bordered container used for each settings section.
private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.06)))
    }
}
