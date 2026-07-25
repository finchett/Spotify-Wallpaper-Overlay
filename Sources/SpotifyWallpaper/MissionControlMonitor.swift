import AppKit

/// Permission-free Mission Control / App Exposé detection using unredacted window metadata.
final class MissionControlMonitor {
    var onChange: (Bool) -> Void = { _ in }

    private var timer: Timer?
    private var isOpen = false

    func start() {
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isOpen = false
    }

    private func tick() {
        let open = Self.workspaceViewerVisible()
        guard open != isOpen else { return }
        isOpen = open
        onChange(open)
    }

    private static func workspaceViewerVisible() -> Bool {
        let screenSizes = NSScreen.screens.map(\.frame.size)
        guard !screenSizes.isEmpty,
              let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for window in list {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let boundsDictionary =
                    window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(
                    dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                continue
            }

            // Titles are redacted without Screen Recording permission. Current macOS uses
            // an unredacted WindowManager shield at layer 19. The named Dock path retains
            // compatibility where titles are available.
            let name = window[kCGWindowName as String] as? String
            let isWorkspaceWindow =
                (owner == "WindowManager" && layer == 19) ||
                (owner == "Dock" && layer == 20 && name == "Dock")
            guard isWorkspaceWindow else { continue }

            if screenSizes.contains(where: { size in
                bounds.width >= size.width * 0.9 &&
                bounds.height >= size.height * 0.9
            }) {
                return true
            }
        }
        return false
    }
}
