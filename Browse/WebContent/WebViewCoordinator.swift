import WebKit

@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate,
                                           WKScriptMessageHandler, WKScriptMessageHandlerWithReply {

    weak var viewController: WebViewController?

    private var observations: [NSKeyValueObservation] = []
    private let filter = ContentFilterService.shared
    private var processedElementIds = Set<String>()
    private var imageCount = 0

    // MARK: - Tab Lifecycle

    func observe(_ webView: WKWebView, for tab: BrowserTab) {
        observations.removeAll()

        observations.append(
            webView.observe(\.title) { [weak tab] wv, _ in
                Task { @MainActor in tab?.title = wv.title ?? "Untitled" }
            }
        )
        observations.append(
            webView.observe(\.url) { [weak tab] wv, _ in
                Task { @MainActor in tab?.url = wv.url }
            }
        )
        observations.append(
            webView.observe(\.isLoading) { [weak tab] wv, _ in
                Task { @MainActor in tab?.isLoading = wv.isLoading }
            }
        )
        observations.append(
            webView.observe(\.canGoBack) { [weak tab] wv, _ in
                Task { @MainActor in tab?.canGoBack = wv.canGoBack }
            }
        )
        observations.append(
            webView.observe(\.canGoForward) { [weak tab] wv, _ in
                Task { @MainActor in tab?.canGoForward = wv.canGoForward }
            }
        )
        observations.append(
            webView.observe(\.estimatedProgress) { [weak tab] wv, _ in
                Task { @MainActor in tab?.estimatedProgress = wv.estimatedProgress }
            }
        )
    }

    /// Register content filter message handlers on a web view's user content controller.
    /// Call this once per tab when the web view is first displayed.
    func registerMessageHandlers(on webView: WKWebView) {
        let ucc = webView.configuration.userContentController

        // Fire-and-forget handlers (images, logs)
        ucc.add(self, name: "imageFound")
        ucc.add(self, name: "scanLog")
        ucc.add(self, name: "videoLog")

        // Reply-based handler (video frames — JS awaits classification result)
        ucc.addScriptMessageHandler(self, contentWorld: .page, name: "videoFrame")
    }

    /// Remove message handlers to prevent retain cycles.
    func unregisterMessageHandlers(on webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.removeScriptMessageHandler(forName: "imageFound")
        ucc.removeScriptMessageHandler(forName: "scanLog")
        ucc.removeScriptMessageHandler(forName: "videoLog")
        ucc.removeScriptMessageHandler(forName: "videoFrame", contentWorld: .page)
    }

    /// Reset per-tab state when switching tabs.
    func resetFilterState() {
        processedElementIds.removeAll()
        imageCount = 0
    }

    // MARK: - WKScriptMessageHandlerWithReply (videoFrame)

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard message.name == "videoFrame" else { return (nil, nil) }
        let result = await handleVideoFrame(message)
        return (result, nil)
    }

    // MARK: - WKScriptMessageHandler (imageFound, scanLog, videoLog)

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "imageFound":
            Task { await handleImage(message) }
        case "scanLog":
            if let msg = message.body as? String { print("[IMG-JS] \(msg)") }
        case "videoLog":
            if let msg = message.body as? String { print("[VID-JS] \(msg)") }
        default:
            break
        }
    }

    // MARK: - Image Handling

    private func handleImage(_ message: WKScriptMessage) async {
        guard let body = message.body as? [String: Any],
              let dataURL = body["imageData"] as? String,
              let elementId = body["elementId"] as? String,
              let src = body["src"] as? String
        else { return }

        let needsNativeFetch = body["needsNativeFetch"] as? Bool ?? false
        let webView = message.webView

        guard !processedElementIds.contains(elementId) else { return }
        processedElementIds.insert(elementId)

        imageCount += 1
        let idx = imageCount
        print("[NSFW] #\(idx) \(needsNativeFetch ? "native-fetch" : "js-data") src: \(src.prefix(80))")

        guard filter.isModelLoaded else {
            _ = try? await webView?.evaluateJavaScript(Self.revealImageJS(elementId: elementId))
            return
        }

        let cg: CGImage
        if needsNativeFetch {
            guard let resolved = await filter.fetchImageNatively(src: src) else {
                _ = try? await webView?.evaluateJavaScript(Self.revealImageJS(elementId: elementId))
                return
            }
            cg = resolved
        } else {
            guard let resolved = filter.decodeCGImage(from: dataURL) else {
                _ = try? await webView?.evaluateJavaScript(Self.revealImageJS(elementId: elementId))
                return
            }
            cg = resolved
        }

        if let results = await filter.classifyImage(cg) {
            let allResults = filter.formatResults(results)
            let isSensitive = filter.isNSFW(results)
            print("[NSFW] #\(idx): \(allResults) -> \(isSensitive ? "BLUR" : "SAFE")")

            if isSensitive {
                _ = try? await webView?.evaluateJavaScript(Self.blurImageJS(elementId: elementId))
            } else {
                _ = try? await webView?.evaluateJavaScript(Self.revealImageJS(elementId: elementId))
            }
        } else {
            _ = try? await webView?.evaluateJavaScript(Self.revealImageJS(elementId: elementId))
        }
    }

    // MARK: - Video Frame Handling

    private func handleVideoFrame(_ message: WKScriptMessage) async -> [String: Any]? {
        guard let body = message.body as? [String: Any],
              let frameData = body["frameData"] as? String,
              let elementId = body["elementId"] as? String,
              let src = body["src"] as? String
        else { return nil }

        let currentTime = body["currentTime"] as? Double ?? 0
        let isIframe = body["isIframe"] as? Bool ?? false
        let host = body["host"] as? String ?? "unknown"

        guard filter.isModelLoaded else { return ["blur": false] }

        guard let cg = filter.decodeCGImage(from: frameData) else {
            return ["blur": false]
        }

        let timeStr = String(format: "%.1fs", currentTime)
        let frameTag = isIframe ? "iframe" : "main"
        print("[VID-NSFW] \(frameTag) \(host) \(elementId) @ \(timeStr): \(cg.width)x\(cg.height)")

        if let results = await filter.classifyImage(cg) {
            let allResults = filter.formatResults(results)
            let isSensitive = filter.isNSFW(results)
            print("[VID-NSFW] \(elementId) @ \(timeStr): \(allResults) -> \(isSensitive ? "BLUR" : "SAFE")")
            return ["blur": isSensitive]
        }

        return ["blur": false]
    }

    // MARK: - Blur / Reveal JS

    static func blurImageJS(elementId: String, blurRadius: Int = 30) -> String {
        """
        (function() {
            var el = document.querySelector('[data-sensitive-id="\(elementId)"]');
            if (!el) return 'not_found';
            if (el.__scaTimer) { clearTimeout(el.__scaTimer); el.__scaTimer = null; }
            el.__scaDone = true;
            el.style.filter = 'blur(\(blurRadius)px)';
            el.style.clipPath = 'inset(0)';
            el.style.overflow = 'hidden';
            el.offsetHeight;
            el.setAttribute('data-sca-done', '1');
            el.style.transition = 'opacity 0.15s ease';
            el.style.opacity = '1';
            return 'blurred';
        })();
        """
    }

    static func revealImageJS(elementId: String) -> String {
        """
        (function() {
            var el = document.querySelector('[data-sensitive-id="\(elementId)"]');
            if (!el) return 'not_found';
            if (el.__scaTimer) { clearTimeout(el.__scaTimer); el.__scaTimer = null; }
            el.__scaDone = true;
            el.setAttribute('data-sca-done', '1');
            el.style.opacity = '1';
            return 'revealed';
        })();
        """
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let vc = viewController else { return }
            vc.onNavigationFinished()

            // Re-inject image scanner after navigation completes
            if let scannerURL = Bundle.main.url(forResource: "image-scanner", withExtension: "js"),
               let scannerSource = try? String(contentsOf: scannerURL) {
                webView.evaluateJavaScript(scannerSource, completionHandler: nil)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command) {
            if let url = navigationAction.request.url {
                viewController?.openURLInNewTab(url)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

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
}
