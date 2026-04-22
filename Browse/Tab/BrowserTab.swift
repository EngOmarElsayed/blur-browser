import AppKit
import WebKit

@Observable
@MainActor
final class BrowserTab: Identifiable {
    let id: UUID
    var url: URL?
    var title: String
    var isLoading: Bool = false
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var estimatedProgress: Double = 0
    var faviconImage: NSImage?
    var isPinned: Bool = false
    var browsingError: BrowsingError?

    /// Cached parsed article when reader mode is active for this tab.
    /// `nil` means reader mode is off for this tab.
    var readerArticle: ReaderArticle?

    /// The URL that `readerArticle` was parsed from. Used to invalidate the cache
    /// when the tab navigates to a different page while reader state is held.
    var readerParsedForURL: URL?

    /// True while a provisional navigation is in flight (before commit or failure).
    /// While true, KVO updates to `url` are ignored so the intended URL stays visible
    /// in the address bar even if WKWebView reverts its internal URL on failure.
    var isProvisionalNavigationInFlight: Bool = false

    /// When this tab is in "new tab" state (url == AppConstants.newTabURL), this
    /// holds the wallpaper filename (no extension) chosen from the active theme.
    /// Nil otherwise. Refreshed by BrowserWindowController on theme change.
    var newTabWallpaperName: String?

    let webView: WKWebView
    private var observations: [NSKeyValueObservation] = []

    init(url: URL? = nil, configuration: WKWebViewConfiguration? = nil) {
        self.id = UUID()
        self.url = url
        self.title = "New Tab"

        let config = configuration ?? Self.makeFilterConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        self.webView = wv

        // Start observing immediately so progress/loading state is tracked
        // from the moment the page starts loading
        observeWebView(wv)

        // Sync the initial color scheme to the active theme
        Self.syncColorScheme(wv)

        // Pick a wallpaper for new-tab state; WebViewController reads this.
        if url == AppConstants.newTabURL {
            newTabWallpaperName = ThemeStore.shared.current.wallpaperNames.randomElement()
        }

        if let url {
            Self.load(url, on: wv)
        }
    }

    /// Load a URL into a WKWebView, picking the right API for the scheme.
    /// `file://` URLs use `loadFileURL(_:allowingReadAccessTo:)` with the parent
    /// directory so adjacent CSS/JS/image assets can be resolved.
    static func load(_ url: URL, on webView: WKWebView) {
        // New-tab URL is rendered natively via NewTabWallpaperView rather than
        // loaded through WKWebView — skip the WebKit round-trip entirely.
        if url == AppConstants.newTabURL {
            return
        }
        if url.isFileURL {
            let readAccess = url.deletingLastPathComponent()
            webView.loadFileURL(url, allowingReadAccessTo: readAccess)
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    private func observeWebView(_ wv: WKWebView) {
        observations.append(
            wv.observe(\.estimatedProgress) { [weak self] wv, _ in
                Task { @MainActor in self?.estimatedProgress = wv.estimatedProgress }
            }
        )
        observations.append(
            wv.observe(\.isLoading) { [weak self] wv, _ in
                Task { @MainActor in self?.isLoading = wv.isLoading }
            }
        )
        observations.append(
            wv.observe(\.title) { [weak self] wv, _ in
                Task { @MainActor in self?.title = wv.title ?? "Untitled" }
            }
        )
        observations.append(
            wv.observe(\.url) { [weak self] wv, _ in
                // Don't clear the stored URL when WKWebView's URL becomes nil
                // (happens on failed provisional navigations) — keep the intended
                // URL visible in the address bar so the user knows what they tried to load.
                Task { @MainActor in
                    guard let self, let newURL = wv.url else { return }
                    // While a provisional navigation is in flight, WKWebView may
                    // revert its url to the last committed URL on failure. Ignore
                    // those reverts so the intended URL stays visible.
                    if self.isProvisionalNavigationInFlight { return }
                    self.url = newURL
                    // Invalidate cached reader article if the page navigated away
                    if let parsedURL = self.readerParsedForURL, parsedURL != newURL {
                        self.readerArticle = nil
                        self.readerParsedForURL = nil
                    }
                }
            }
        )
        observations.append(
            wv.observe(\.canGoBack) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoBack = wv.canGoBack }
            }
        )
        observations.append(
            wv.observe(\.canGoForward) { [weak self] wv, _ in
                Task { @MainActor in self?.canGoForward = wv.canGoForward }
            }
        )
    }

    var displayTitle: String {
        if title.isEmpty || title == "New Tab" {
            return url?.host ?? "New Tab"
        }
        return title
    }

    var displayURL: String {
        // Internal new-tab URL is an implementation detail — show an empty
        // address bar so the placeholder ("Search or enter URL...") is visible.
        if url == AppConstants.newTabURL { return "" }
        return url?.absoluteString ?? ""
    }

    /// Favicon URL derived from the current page's host using Google's favicon service.
    var faviconURL: URL? {
        guard let host = url?.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=32&domain=\(host)")
    }

    // MARK: - WKWebView Configuration with Content Filter Scripts

    /// Shared process pool for all tabs — lets them share cookies and session
    /// state within a single run of the app.
    private static let sharedProcessPool = WKProcessPool()

    private static func makeFilterConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "fullScreenEnabled")
        config.preferences.isElementFullscreenEnabled = true
        config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"

        // Share the default (persistent) website data store across all tabs so
        // cookies, local storage, and session state survive across app launches.
        config.websiteDataStore = .default()
        config.processPool = BrowserTab.sharedProcessPool

        // Early hide — documentStart, all frames
        if let earlyHideURL = Bundle.main.url(forResource: "content-filter", withExtension: "js"),
           let earlyHideSource = try? String(contentsOf: earlyHideURL) {
            let earlyHide = WKUserScript(
                source: earlyHideSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(earlyHide)
        }

        // Image scanner — documentEnd, all frames
        if let imageScannerURL = Bundle.main.url(forResource: "image-scanner", withExtension: "js"),
           let imageScannerSource = try? String(contentsOf: imageScannerURL) {
            let imageScanner = WKUserScript(
                source: imageScannerSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(imageScanner)
        }

        // Video scanner — documentEnd, all frames
        if let videoScannerURL = Bundle.main.url(forResource: "video-scanner", withExtension: "js"),
           let videoScannerSource = try? String(contentsOf: videoScannerURL) {
            let videoScanner = WKUserScript(
                source: videoScannerSource,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
            config.userContentController.addUserScript(videoScanner)
        }

        // Register blur:// and blur-image:// scheme handlers for the themed new tab page.
        let blurHandler = BlurSchemeHandler()
        config.setURLSchemeHandler(blurHandler, forURLScheme: "blur")
        config.setURLSchemeHandler(blurHandler, forURLScheme: "blur-image")

        return config
    }

    /// Apply the active theme's `isDark` flag to the web view's appearance and
    /// under-page background so websites react to `prefers-color-scheme` and
    /// the chrome/content boundary doesn't flash during scroll or navigation.
    static func syncColorScheme(_ wv: WKWebView) {
        let theme = ThemeStore.shared.current
        // Match the chrome so elastic scroll and between-navigation gaps don't flash.
        wv.underPageBackgroundColor = theme.chromeColor
        // Appearance affects system color scheme inside WKWebView (e.g. prefers-color-scheme).
        wv.appearance = theme.isDark
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
    }
}

extension BrowserTab: @preconcurrency Hashable {
    static func == (lhs: BrowserTab, rhs: BrowserTab) -> Bool {
        lhs.id == rhs.id
    }
    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
