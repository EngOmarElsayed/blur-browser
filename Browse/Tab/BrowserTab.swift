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

    let webView: WKWebView

    init(url: URL? = nil, configuration: WKWebViewConfiguration? = nil) {
        self.id = UUID()
        self.url = url
        self.title = "New Tab"

        let config = configuration ?? Self.makeFilterConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = AppConstants.userAgent
        wv.allowsBackForwardNavigationGestures = true
        self.webView = wv

        if let url {
            wv.load(URLRequest(url: url))
        }
    }

    var displayTitle: String {
        if title.isEmpty || title == "New Tab" {
            return url?.host ?? "New Tab"
        }
        return title
    }

    var displayURL: String {
        url?.absoluteString ?? ""
    }

    // MARK: - WKWebView Configuration with Content Filter Scripts

    private static func makeFilterConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

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

        return config
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
