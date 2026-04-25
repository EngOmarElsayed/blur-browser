import WebKit

@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply {

    weak var viewController: WebViewController?
    weak var downloadManager: DownloadManager?

    private let filter = ContentFilterService.shared
    private var processedElementIds = Set<String>()
    private var imageCount = 0

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
        // CSS `filter: blur()` fades the element's edges toward transparent
        // (the blur kernel samples "outside" as transparent pixels), which on
        // sites like Twitter/X lets the underlying image leak through the
        // perimeter. Clip-path alone preserves that inner fade.
        //
        // Fix: also apply `transform: scale(1.25)` so the faded edge halo is
        // pushed outside the parent container's `overflow: hidden` clip,
        // leaving only the fully-blurred interior visible. Use !important so
        // site CSS / React re-renders can't override us mid-frame.
        """
        (function() {
            var el = document.querySelector('[data-sensitive-id="\(elementId)"]');
            if (!el) return 'not_found';
            if (el.__scaTimer) { clearTimeout(el.__scaTimer); el.__scaTimer = null; }
            el.__scaDone = true;
            el.style.setProperty('filter', 'blur(\(blurRadius)px)', 'important');
            el.style.setProperty('clip-path', 'inset(0)', 'important');
            el.style.setProperty('transform', 'scale(1.6)', 'important');
            el.style.setProperty('transform-origin', '50% 50%', 'important');
            // Also blur immediate parent container — Twitter/X often lets the
            // img's fade halo leak past the container's rounded clip. Blurring
            // the parent's rendered output makes the perimeter unrecognizable
            // regardless of the element-level fade.
            var __scaParent = el.parentElement;
            if (__scaParent && !__scaParent.__scaParentBlurred) {
                __scaParent.__scaParentBlurred = true;
                __scaParent.__scaParentOrigFilter = __scaParent.style.filter || '';
                __scaParent.style.setProperty('filter', 'blur(12px)', 'important');
                __scaParent.style.setProperty('overflow', 'hidden', 'important');
            }
            el.offsetHeight;
            el.setAttribute('data-sca-done', '1');
            el.removeAttribute('data-sca-safe');
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
            el.style.removeProperty('filter');
            el.style.removeProperty('clip-path');
            el.style.removeProperty('transform');
            el.style.removeProperty('transform-origin');
            var __scaParent = el.parentElement;
            if (__scaParent && __scaParent.__scaParentBlurred) {
                __scaParent.__scaParentBlurred = false;
                if (__scaParent.__scaParentOrigFilter) {
                    __scaParent.style.filter = __scaParent.__scaParentOrigFilter;
                } else {
                    __scaParent.style.removeProperty('filter');
                }
            }
            el.setAttribute('data-sca-done', '1');
            el.setAttribute('data-sca-safe', '1');
            el.style.opacity = '1';
            return 'revealed';
        })();
        """
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        viewController?.tabForWebView(webView)?.isProvisionalNavigationInFlight = true
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        viewController?.tabForWebView(webView)?.isProvisionalNavigationInFlight = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let tab = viewController?.tabForWebView(webView)
        tab?.isProvisionalNavigationInFlight = false
        guard let vc = viewController else { return }
        vc.clearErrorPage()
        vc.onNavigationFinished()

        // Ask the page for its real declared favicon (overrides the optimistic
        // /favicon.ico guess set on URL change).
        tab?.extractFavicon()

        // Re-inject image scanner after navigation completes
        if let scannerURL = Bundle.main.url(forResource: "image-scanner", withExtension: "js"),
           let scannerSource = try? String(contentsOf: scannerURL) {
            webView.evaluateJavaScript(scannerSource, completionHandler: nil)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        viewController?.tabForWebView(webView)?.isProvisionalNavigationInFlight = false
        let nsError = error as NSError
        if let browsingError = BrowsingError.from(nsError) {
            viewController?.showErrorPage(browsingError)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Keep isProvisionalNavigationInFlight true for the rest of this call
        // so the KVO that fires as WKWebView reverts its url (to the previous
        // committed URL) is ignored. Clear the flag on the next runloop tick
        // after the KVO has fired and been filtered out.
        let tab = viewController?.tabForWebView(webView)
        let nsError = error as NSError
        if let browsingError = BrowsingError.from(nsError) {
            viewController?.showErrorPage(browsingError)
        }
        DispatchQueue.main.async {
            tab?.isProvisionalNavigationInFlight = false
        }
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

        // Update tab.url as soon as a main-frame navigation begins, so the
        // address bar reflects the target URL immediately and retry works
        // even when the navigation fails provisionally.
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url,
           let tab = viewController?.tabForWebView(webView) {
            tab.url = url
        }

        decisionHandler(.allow)
    }

    // MARK: - Download detection

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let response = navigationResponse.response
        let mime = response.mimeType ?? ""
        let isDownloadableMime = Self.downloadableMimeTypes.contains(mime)

        var contentDisposition = ""
        if let httpResponse = response as? HTTPURLResponse,
           let disp = httpResponse.value(forHTTPHeaderField: "Content-Disposition") {
            contentDisposition = disp
        }
        let hasAttachment = contentDisposition.lowercased().contains("attachment")

        // If the web view can't render the MIME type OR the server explicitly
        // flagged it as an attachment → turn into a download.
        if hasAttachment || isDownloadableMime || !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }
        decisionHandler(.allow)
    }

    /// Called when a navigation action becomes a download (e.g. <a download> links).
    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        let url = navigationAction.request.url ?? webView.url
        let expected = navigationAction.request.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }
        downloadManager?.beginDownload(download, sourceURL: url, expectedSize: expected)
        revertTabURLAfterDownload(webView: webView)
    }

    /// Called when a navigation response becomes a download (attachment/unknown MIME).
    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        let url = webView.url
        let expected: Int64? = {
            let len = navigationResponse.response.expectedContentLength
            return len > 0 ? len : nil
        }()
        downloadManager?.beginDownload(download, sourceURL: url, expectedSize: expected)
        revertTabURLAfterDownload(webView: webView)
    }

    /// We optimistically update `tab.url` in `decidePolicyFor navigationAction` so
    /// the address bar reflects the target URL as soon as navigation begins.
    /// When that navigation is promoted to a download, it never commits — the
    /// user stayed on the previous page (or on no page at all for a fresh tab).
    /// Revert `tab.url` to the web view's last committed URL (which may be nil
    /// for a fresh tab — that's correct, the address bar should be blank in that
    /// case, not show the download URL).
    private func revertTabURLAfterDownload(webView: WKWebView) {
        guard let tab = viewController?.tabForWebView(webView) else { return }
        tab.url = webView.url
    }

    /// MIME types we always treat as downloads even if WKWebView could render them.
    private static let downloadableMimeTypes: Set<String> = [
        "application/octet-stream",
        "application/zip",
        "application/x-zip-compressed",
        "application/x-gzip",
        "application/x-tar",
        "application/x-7z-compressed",
        "application/x-rar-compressed",
        "application/x-bzip2",
        "application/vnd.microsoft.portable-executable",
        "application/x-msdownload",
        "application/x-apple-diskimage",
        "application/java-archive",
    ]

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

    // MARK: - JavaScript Dialogs (alert / confirm / prompt)
    //
    // WKWebView silently no-ops these unless we implement the WKUIDelegate
    // methods. Without confirm(), GitHub-style "discard unsaved changes?"
    // prompts effectively auto-answer "OK", letting navigation through.

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "JavaScript"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        guard let window = webView.window else {
            completionHandler()
            return
        }
        alert.beginSheetModal(for: window) { _ in
            completionHandler()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "JavaScript"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard let window = webView.window else {
            completionHandler(false)
            return
        }
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = frame.request.url?.host ?? "JavaScript"
        alert.informativeText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input

        guard let window = webView.window else {
            completionHandler(nil)
            return
        }
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    // MARK: - File Upload Panel

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        self.viewController?.showFileUploadPanel(
            allowsMultipleSelection: parameters.allowsMultipleSelection,
            allowsDirectories: parameters.allowsDirectories,
            completionHandler: completionHandler
        )
    }

    // MARK: - Media Capture Permission (Camera / Microphone)
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        print("[Permission] requestMediaCapture from \(origin.host), type: \(type.rawValue)")

        let permType: PermissionBannerView.PermissionType
        switch type {
        case .camera:              permType = .camera
        case .microphone:          permType = .microphone
        case .cameraAndMicrophone: permType = .cameraAndMicrophone
        @unknown default:          permType = .camera
        }

        // Check saved policy before showing banner
        let store = SitePermissionStore.shared
        let siteTypes = permType.sitePermissionTypes
        let policies = siteTypes.map { store.effectivePolicy(for: origin.host, type: $0) }

        if policies.contains(.deny) {
            decisionHandler(.deny)
            return
        }
        if policies.allSatisfy({ $0 == .allow }) {
            decisionHandler(.grant)
            return
        }
        self.viewController?.showPermissionBanner(type: permType, host: origin.host) { allowed in
            decisionHandler(allowed ? .grant : .deny)
        }
    }

    // MARK: - Geolocation Permission
    func webView(
        _ webView: WKWebView,
        requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping  @Sendable (WKPermissionDecision) -> Void
    ) {
        let store = SitePermissionStore.shared
        let policy = store.effectivePolicy(for: origin.host, type: .location)

        switch policy {
        case .allow:
            decisionHandler(.grant)
        case .deny:
            decisionHandler(.deny)
        case .ask:
            self.viewController?.showPermissionBanner(type: .location, host: origin.host) { allowed in
                decisionHandler(allowed ? .grant : .deny)
            }
        }
    }

    // MARK: - HTTP Authentication

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace
        print("[Auth] didReceive challenge: method=\(protectionSpace.authenticationMethod), host=\(protectionSpace.host), realm=\(protectionSpace.realm ?? "nil")")

        // Handle server trust (HTTPS certificate) — defer to WebKit's default
        // validation. WebKit does full modern TLS validation: AIA chasing to
        // fetch missing intermediate certs, async OCSP/CRL revocation checks,
        // Certificate Transparency, and hostname matching. A manual
        // SecTrustEvaluateWithError call here would be stricter than needed and
        // reject legitimate sites whose servers don't ship full chains
        // (e.g., new sites with minimal TLS setup).
        //
        // When WebKit's validation fails, it fires didFailProvisionalNavigation
        // with NSURLErrorServerCertificateUntrusted (or similar), which our
        // error-page flow classifies as .sslError.
        //
        // The only override: allow self-signed certs on loopback hosts so
        // local dev servers (mkcert, etc.) keep working.
        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            let host = protectionSpace.host.lowercased()
            let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")

            if isLoopback, let trust = protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        // Handle HTTP Basic/Digest authentication
        if protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPBasic ||
           protectionSpace.authenticationMethod == NSURLAuthenticationMethodHTTPDigest {

            let host = protectionSpace.host
            let realm = protectionSpace.realm

            // If we've already failed too many times, cancel
            if challenge.previousFailureCount >= 3 {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            self.viewController?.showAuthenticationDialog(host: host, realm: realm) { username, password in
                if let username, let password {
                    let credential = URLCredential(
                        user: username,
                        password: password,
                        persistence: .forSession
                    )
                    completionHandler(.useCredential, credential)
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
            }
            return
        }

        // All other auth methods — default handling
        completionHandler(.performDefaultHandling, nil)
    }
}
