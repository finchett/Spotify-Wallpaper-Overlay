import AppKit

// Regular app: dock icon + settings window. The desktop overlay runs behind everything,
// and the menu-bar icon is an optional extra toggled from the settings window.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Dock icon vs. background agent, per the saved preference (toggleable at runtime).
app.setActivationPolicy(Settings.showDockIcon ? .regular : .accessory)
app.run()
