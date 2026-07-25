import AppKit
import WebKit

/// Presents a Spotify login window in a WKWebView and captures the `sp_dc` cookie the
/// moment it appears — no manual DevTools cookie hunting. Feeds Credentials.save(spDc:).
final class SpotifyLoginController: NSObject {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var onComplete: ((Bool) -> Void)?
    private var finished = false

    func present(onComplete: @escaping (Bool) -> Void) {
        self.onComplete = onComplete
        self.finished = false

        // Persistent default store: if there's already a logged-in session, sp_dc is
        // available immediately; otherwise the user logs in and it gets set.
        let dataStore = WKWebsiteDataStore.default()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 660), configuration: config)
        webView = web
        dataStore.httpCookieStore.add(self)

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 660),
                           styleMask: [.titled, .closable],
                           backing: .buffered, defer: false)
        win.title = "Log in to Spotify"
        win.contentView = web
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        let login = URL(string: "https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com%2F")!
        web.load(URLRequest(url: login))

        checkForCookie()   // in case a valid session is already stored
    }

    private func checkForCookie() {
        guard let store = webView?.configuration.websiteDataStore.httpCookieStore else { return }
        store.getAllCookies { [weak self] cookies in
            guard let self, !self.finished else { return }
            if let spDc = cookies.first(where: { $0.name == "sp_dc" && !$0.value.isEmpty }) {
                self.finish(success: true, value: spDc.value)
            }
        }
    }

    private func finish(success: Bool, value: String?) {
        guard !finished else { return }
        finished = true
        if let value { Credentials.save(spDc: value) }

        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        window?.delegate = nil
        window?.close()
        window = nil
        webView = nil

        onComplete?(success)
        onComplete = nil
    }
}

extension SpotifyLoginController: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        checkForCookie()
    }
}

extension SpotifyLoginController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // User closed the window without completing login.
        finish(success: false, value: nil)
    }
}
