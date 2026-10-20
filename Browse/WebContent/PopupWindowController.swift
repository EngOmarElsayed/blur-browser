import AppKit
import WebKit

/// A small window for `window.open(url, name, "width=…,height=…")` popups —
/// "Sign in with Google/Apple" and other OAuth flows.
///
/// The popup's web view must be built from the configuration WebKit hands to
/// `createWebViewWith`, so `window.opener` stays connected to the page that
/// opened it; that link is how the sign-in result gets back. With no address
/// bar, the window title shows the popup's host so the user can see where
/// they're signing in.
@MainActor
final class PopupWindowController: NSWindowController, NSWindowDelegate, WKUIDelegate {

    /// Open popups. Each one keeps itself alive until its window closes.
    private static var open: Set<PopupWindowController> = []

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []

    /// Builds the popup around WebKit's configuration and shows it centered
    /// over `parent`. Returns the web view WebKit should load into.
    static func present(
        configuration: WKWebViewConfiguration,
        windowFeatures: WKWindowFeatures,
        over parent: NSWindow?
    ) -> WKWebView {
        let width = windowFeatures.width.map { CGFloat(truncating: $0) } ?? 500
        let height = windowFeatures.height.map { CGFloat(truncating: $0) } ?? 640
        let size = NSSize(width: max(320, min(width, 1200)), height: max(240, min(height, 1000)))

        let controller = PopupWindowController(configuration: configuration, size: size)
        open.insert(controller)

        if let window = controller.window {
            if let parent {
                let frame = parent.frame
                window.setFrameOrigin(NSPoint(
                    x: frame.midX - window.frame.width / 2,
                    y: frame.midY - window.frame.height / 2))
            } else {
                window.center()
            }
            controller.showWindow(nil)
        }
        return controller.webView
    }

    private init(configuration: WKWebViewConfiguration, size: NSSize) {
        webView = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.titlebarSeparatorStyle = .line
        window.contentView = webView
        super.init(window: window)

        window.delegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]
        BrowserTab.syncColorScheme(webView)

        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateTitle() }
            },
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateTitle() }
            },
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Host as the title (where you're signing in), page title underneath.
    private func updateTitle() {
        let host = webView.url?.host() ?? "Loading…"
        window?.title = host
        window?.subtitle = webView.title ?? ""
    }

    // MARK: - WKUIDelegate

    /// The page called `window.close()` — typically once sign-in finished.
    func webViewDidClose(_ webView: WKWebView) {
        window?.close()
    }

    /// A popup opening another window: keep it in this popup.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        observations.removeAll()
        webView.stopLoading()
        webView.uiDelegate = nil
        Self.open.remove(self)
    }
}
