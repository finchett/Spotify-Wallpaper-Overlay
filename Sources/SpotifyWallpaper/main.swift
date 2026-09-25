import AppKit

// Regular app: dock icon + settings window. The desktop overlay runs behind everything,
// and the menu-bar icon is an optional extra toggled from the settings window.
let app = NSApplication.shared

// Two copies would each bake the wallpaper and save the other's baked store as the
// "original", losing the real wallpaper. Hand off to the running copy instead.
if let bundleID = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .contains(where: { $0 != .current }) {
    DistributedNotificationCenter.default().postNotificationName(
        AppDelegate.showSettingsNotification, object: nil,
        userInfo: nil, deliverImmediately: true)
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
// Dock icon vs. background agent, per the saved preference (toggleable at runtime).
app.setActivationPolicy(Settings.showDockIcon ? .regular : .accessory)
app.run()
