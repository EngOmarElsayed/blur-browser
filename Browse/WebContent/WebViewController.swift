import AppKit
import SwiftUI
import WebKit

@MainActor
final class WebViewController: NSViewController {

    private let tabManager: TabManager
    private let coordinator = WebViewCoordinator()
    private let passwordStore: PasswordStore
    private let blocklistStore: BlocklistStore
    private(set) var passwordCoordinator: PasswordManagerCoordinator?
    private var currentWebView: WKWebView?
    private var findBar: FindInPageBar?
    private var findController: FindInPageController?
    private var historyStore: HistoryStore?
    private var quickSearchOverlay: QuickSearchOverlay?
    private var errorPageHosting: NSHostingController<ErrorPageView>?

    var onNewTabRequested: ((URL) -> Void)?

    /// Called when a finished page has been checked for reader-mode availability.
    var onReaderAvailabilityChanged: ((Bool) -> Void)?

    init(tabManager: TabManager,
         passwordStore: PasswordStore,
         blocklistStore: BlocklistStore) {
        self.tabManager = tabManager
        self.passwordStore = passwordStore
        self.blocklistStore = blocklistStore
        super.init(nibName: nil, bundle: nil)
        coordinator.viewController = self
        let pmCoordinator = PasswordManagerCoordinator(
            passwordStore: passwordStore,
            blocklistStore: blocklistStore
        )
        self.passwordCoordinator = pmCoordinator
        observePasswordCoordinator()

        pmCoordinator.onAutofillPresent = { [weak self] rectInDoc, creds, form, _ in
            self?.presentAutofill(rectInDoc: rectInDoc, credentials: creds, form: form)
        }
        pmCoordinator.onAutofillDismiss = { [weak self] in
            self?.autofillPanel.hide()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private let cornerMaskView = CornerMaskView()

    /// Top-left overlay for the password Save/Update prompt. Mirrors the
    /// coordinator's `pendingSaveCredential` via a 50ms polling Task (same
    /// pattern as BrowserWindowController's tab-selection observer).
    private let savePromptOverlay = SavePromptOverlay()

    /// Autofill credentials popover. Anchored just below the focused login
    /// field; shown by `presentAutofill(rectInDoc:credentials:form:)` and
    /// hidden on blur, scroll, click-outside, tab switch, or window deactivate.
    private let autofillPanel = AutofillPopoverPanel()

    /// Native wallpaper overlay shown on top of the web view whenever the current
    /// tab is on `AppConstants.newTabURL`. Replaces the old blur://newtab HTML path.
    private let wallpaperView = NewTabWallpaperView()

    /// SwiftUI Privacy Report widget shown above the wallpaper on the new
    /// tab page. Same show/hide rules as `wallpaperView` — visible only when
    /// the active tab is on the new-tab URL.
    private lazy var privacyReportHostingView: NSHostingView<PrivacyReportView> = {
        let host = NSHostingView(rootView: PrivacyReportView())
        host.translatesAutoresizingMaskIntoConstraints = true
        return host
    }()

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutCurrentWebView()
        quickSearchOverlay?.layoutInParent(view)
    }

    func setHistoryStore(_ store: HistoryStore) {
        self.historyStore = store
    }

    func setQuickSearchOverlay(_ overlay: QuickSearchOverlay) {
        self.quickSearchOverlay = overlay
    }

    func setDownloadManager(_ manager: DownloadManager) {
        coordinator.downloadManager = manager
    }

    func displayTab(_ tab: BrowserTab?) {
        // Reset reader availability for the new tab (we'll re-check on navigation finish)
        onReaderAvailabilityChanged?(false)

        // A tab swap invalidates any pending save prompt — it was tied to the
        // previous tab's site and submission.
        if currentWebView !== tab?.webView {
            passwordCoordinator?.dismissPending()
            autofillPanel.hide()
        }

        // Clear any error page from previous tab
        errorPageHosting?.view.removeFromSuperview()
        errorPageHosting = nil

        // Exit element fullscreen on the old web view before switching
        if let oldWV = currentWebView {
            oldWV.evaluateJavaScript("if (document.fullscreenElement) { document.exitFullscreen(); }")
            coordinator.unregisterMessageHandlers(on: oldWV)
            oldWV.configuration.userContentController.removeScriptMessageHandler(forName: "passwordManager")
        }

        // Remove old web view
        currentWebView?.removeFromSuperview()
        findBar?.removeFromSuperview()

        guard let tab else {
            currentWebView = nil
            passwordCoordinator?.isTabActive = false
            return
        }
        passwordCoordinator?.isTabActive = true

        let wv = tab.webView
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator

        // Register content filter message handlers
        coordinator.resetFilterState()
        coordinator.registerMessageHandlers(on: wv)

        // Register password manager message handler for the active tab.
        if let pmCoordinator = passwordCoordinator {
            wv.configuration.userContentController.add(pmCoordinator, name: "passwordManager")
            pmCoordinator.webView = wv
        }

        wv.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(wv)
        currentWebView = wv

        // Wallpaper overlay: shown when tab.url == newTabURL, hidden otherwise.
        // Placed above the web view so the "new tab" rendering is instant and
        // doesn't depend on WKWebView loading anything.
        updateNewTabWallpaper(for: tab)

        // Corner mask on top of web view to fake rounded corners
        cornerMaskView.removeFromSuperview()
        view.addSubview(cornerMaskView)

        // Save-password prompt overlay — top-left of the web content area.
        // Hit-tests through to the web view except inside the prompt itself.
        savePromptOverlay.frame = view.bounds
        savePromptOverlay.autoresizingMask = [.width, .height]
        savePromptOverlay.removeFromSuperview()
        view.addSubview(savePromptOverlay, positioned: .above, relativeTo: nil)

        layoutCurrentWebView()

        if let fb = findBar {
            view.addSubview(fb)
            layoutFindBar()
        }

        // If the tab has a saved error, show the error page
        if let error = tab.browsingError {
            showErrorPage(error)
        }

        // Re-check reader availability for this tab. If it's already loaded,
        // `onNavigationFinished` won't fire again, so we need to check explicitly
        // on tab switch.
        if !tab.isLoading, tab.url != nil {
            Task { [weak self] in
                guard let self, let currentWebView = self.currentWebView else { return }
                let available = await ReaderModeService.isReaderable(webView: currentWebView)
                // Only apply if we're still on the same tab
                guard self.currentWebView === tab.webView else { return }
                self.onReaderAvailabilityChanged?(available)
            }
        }
    }

    private func layoutCurrentWebView() {
        guard let wv = currentWebView else { return }
        wv.frame = view.bounds
        cornerMaskView.frame = view.bounds
        // Keep error page (if any) sized to fill the content area
        errorPageHosting?.view.frame = view.bounds
        wallpaperView.frame = view.bounds
        privacyReportHostingView.frame = view.bounds
        // Re-assert z-order: [wkwebview] < [wallpaper] < [privacyReport] < [cornerMask] < [quickSearchOverlay]
        // addSubview without a positioning arg moves the subview to the top.
        if wallpaperView.superview === view {
            wallpaperView.removeFromSuperview()
            view.addSubview(wallpaperView)
        }
        if privacyReportHostingView.superview === view {
            privacyReportHostingView.removeFromSuperview()
            view.addSubview(privacyReportHostingView)
        }
        cornerMaskView.removeFromSuperview()
        view.addSubview(cornerMaskView)

        // Keep the save-password overlay above the corner mask.
        if savePromptOverlay.superview === view {
            savePromptOverlay.frame = view.bounds
            savePromptOverlay.removeFromSuperview()
            view.addSubview(savePromptOverlay)
        }
    }

    // MARK: - New Tab Wallpaper Overlay

    /// Show/hide the native wallpaper overlay based on the tab's URL.
    /// Called from displayTab (tab switch) and refreshNewTabOverlay (URL change).
    private func updateNewTabWallpaper(for tab: BrowserTab?) {
        guard let tab, tab.url == AppConstants.newTabURL else {
            wallpaperView.removeFromSuperview()
            privacyReportHostingView.removeFromSuperview()
            return
        }
        wallpaperView.setWallpaper(named: tab.newTabWallpaperName)
        wallpaperView.frame = view.bounds
        wallpaperView.autoresizingMask = [.width, .height]
        if wallpaperView.superview !== view {
            view.addSubview(wallpaperView)
        }

        // Privacy report overlay sits above wallpaper, below cornerMask.
        privacyReportHostingView.frame = view.bounds
        privacyReportHostingView.autoresizingMask = [.width, .height]
        if privacyReportHostingView.superview !== view {
            view.addSubview(privacyReportHostingView, positioned: .above, relativeTo: wallpaperView)
        }
        // Refresh the snapshot whenever the new-tab page shows. Cheap — the
        // SPI returns instantly from in-process WebKit cache.
        Task { await PrivacyReportStore.shared.refresh() }
    }

    /// Called by the polling loop when the selected tab's URL changes (e.g.
    /// the user navigated from the new-tab page to a real URL). Shows or hides
    /// the wallpaper to match.
    func refreshNewTabOverlay() {
        updateNewTabWallpaper(for: tabManager.selectedTab)
    }

    // MARK: - Navigation

    func goBack() { currentWebView?.goBack() }
    func goForward() { currentWebView?.goForward() }

    func reload(bypassCache: Bool) {
        // If the last navigation failed provisionally, the webView's last committed
        // URL differs from the tab's intended URL. In that case, load the stored
        // URL explicitly instead of calling reload().
        if let tab = tabManager.selectedTab,
           let url = tab.url,
           currentWebView?.url != url {
            currentWebView?.load(URLRequest(url: url))
            return
        }
        if bypassCache {
            currentWebView?.reloadFromOrigin()
        } else {
            currentWebView?.reload()
        }
    }

    // MARK: - Permission Banner

    private var currentPermissionBanner: PermissionBannerView?

    func showPermissionBanner(
        type: PermissionBannerView.PermissionType,
        host: String,
        completion: @escaping (Bool) -> Void
    ) {
        // Remove any existing banner
        currentPermissionBanner?.removeFromSuperview()

        let banner = PermissionBannerView(type: type, host: host)

        // Allow once — grant and register site so it appears in settings
        banner.onAllow = {
            SitePermissionStore.shared.registerSite(host, for: type.sitePermissionTypes)
            completion(true)
        }

        // Always allow — grant and save policy
        banner.onAlwaysAllow = {
            let store = SitePermissionStore.shared
            for permType in type.sitePermissionTypes {
                store.setPolicy(.allow, for: host, type: permType)
            }
            completion(true)
        }

        // Don't allow — deny and save policy
        banner.onDeny = {
            let store = SitePermissionStore.shared
            for permType in type.sitePermissionTypes {
                store.setPolicy(.deny, for: host, type: permType)
            }
            completion(false)
        }

        view.addSubview(banner)
        currentPermissionBanner = banner

        // Center the alert in the web content area
        let w = PermissionBannerView.panelWidth
        let h = PermissionBannerView.panelHeight
        banner.frame = NSRect(
            x: (view.bounds.width - w) / 2,
            y: (view.bounds.height - h) / 2,
            width: w,
            height: h
        )

        // Animate in
        banner.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            banner.animator().alphaValue = 1
        }
    }

    // MARK: - Modal Backdrop (Gaussian blur behind auth/download dialogs)

    /// Gaussian-blur backdrop drawn over the WKWebView while a modal dialog
    /// (auth or download) is visible. Kept here rather than inside each dialog
    /// so the blur animates in sync with the dialog and can be shared by both.
    private var modalBackdrop: GaussianBlurView?

    private func presentModalBackdrop() {
        // If one is already present (rare — two dialogs stacking), reuse it.
        if modalBackdrop != nil { return }

        let blur = GaussianBlurView(radius: 20)
        blur.frame = view.bounds
        blur.layer?.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
        blur.layer?.masksToBounds = true
        blur.alphaValue = 0
        view.addSubview(blur)
        modalBackdrop = blur

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            blur.animator().alphaValue = 1
        }
    }

    private func dismissModalBackdrop() {
        guard let blur = modalBackdrop else { return }
        modalBackdrop = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            blur.animator().alphaValue = 0
        }, completionHandler: {
            blur.removeFromSuperview()
        })
    }

    // MARK: - Authentication Dialog

    private var currentAuthDialog: AuthenticationDialogView?

    func showAuthenticationDialog(
        host: String,
        realm: String?,
        completion: @escaping (String?, String?) -> Void
    ) {
        print("[Auth] showAuthenticationDialog called for host: \(host), realm: \(realm ?? "nil")")
        // Remove any existing dialog
        currentAuthDialog?.removeFromSuperview()

        let dialog = AuthenticationDialogView(host: host, realm: realm)

        dialog.onSubmit = { [weak self] username, password in
            completion(username, password)
            self?.dismissModalBackdrop()
        }

        dialog.onCancel = { [weak self] in
            completion(nil, nil)
            self?.dismissModalBackdrop()
        }

        // Blur first so the dialog sits on top of it
        presentModalBackdrop()
        view.addSubview(dialog)
        currentAuthDialog = dialog

        // Center the dialog in the web content area
        let w = AuthenticationDialogView.panelWidth
        let h = AuthenticationDialogView.panelHeight
        dialog.frame = NSRect(
            x: (view.bounds.width - w) / 2,
            y: (view.bounds.height - h) / 2,
            width: w,
            height: h
        )

        // Animate in
        dialog.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            dialog.animator().alphaValue = 1
        }
    }

    // MARK: - Download Confirmation

    private var currentDownloadDialog: DownloadConfirmationView?

    func showDownloadConfirmation(
        filename: String,
        host: String?,
        expectedSize: Int64?,
        completion: @escaping (Bool) -> Void
    ) {
        currentDownloadDialog?.removeFromSuperview()

        let dialog = DownloadConfirmationView(filename: filename, host: host, expectedSize: expectedSize)
        dialog.onAllow = { [weak self] in
            completion(true)
            self?.dismissModalBackdrop()
        }
        dialog.onDeny = { [weak self] in
            completion(false)
            self?.dismissModalBackdrop()
        }

        // Blur first so the dialog sits on top of it
        presentModalBackdrop()
        view.addSubview(dialog)
        currentDownloadDialog = dialog

        let w = DownloadConfirmationView.panelWidth
        let h = DownloadConfirmationView.panelHeight
        dialog.frame = NSRect(
            x: (view.bounds.width - w) / 2,
            y: (view.bounds.height - h) / 2,
            width: w,
            height: h
        )

        dialog.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            dialog.animator().alphaValue = 1
        }
    }

    // MARK: - File Upload Panel

    private var dimOverlay: NSView?

    func showFileUploadPanel(
        allowsMultipleSelection: Bool,
        allowsDirectories: Bool,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        // Add dim overlay
        let overlay = NSView(frame: view.bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        overlay.autoresizingMask = [.width, .height]
        view.addSubview(overlay)
        dimOverlay = overlay

        // Fade in
        overlay.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            overlay.animator().alphaValue = 1
        }

        // Show open panel as sheet on the browser window
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseFiles = true
        panel.canChooseDirectories = allowsDirectories

        guard let window = view.window else {
            // Fallback: show standalone
            panel.begin { [weak self] response in
                self?.dismissDimOverlay()
                completionHandler(response == .OK ? panel.urls : nil)
            }
            return
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            self?.dismissDimOverlay()
            completionHandler(response == .OK ? panel.urls : nil)
        }
    }

    private func dismissDimOverlay() {
        guard let overlay = dimOverlay else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            overlay.animator().alphaValue = 0
        }, completionHandler: {
            overlay.removeFromSuperview()
        })
        dimOverlay = nil
    }

    func onNavigationFinished() {
        guard let tab = tabManager.selectedTab, let url = tab.url else { return }
        // Don't record internal pages (new-tab page, etc.) in browsing history.
        if url.scheme != "blur" {
            historyStore?.addEntry(url: url, title: tab.title)
        }

        // Check if this page can be displayed in reader mode
        Task { [weak self] in
            guard let self, let currentWebView = self.currentWebView else { return }
            let available = await ReaderModeService.isReaderable(webView: currentWebView)
            // Only apply the result if we're still on the same tab/page
            guard self.currentWebView === tab.webView else { return }
            self.onReaderAvailabilityChanged?(available)
        }
    }

    // MARK: - Error Page

    func showErrorPage(_ error: BrowsingError) {
        // Store error on the current tab
        tabManager.selectedTab?.browsingError = error

        // Remove any existing error overlay view (without clearing stored state)
        errorPageHosting?.view.removeFromSuperview()
        errorPageHosting = nil

        let errorView = ErrorPageView(error: error) { [weak self] in
            // Load the tab's stored (intended) URL rather than calling reload(),
            // because reload() would navigate to the last *committed* URL, not
            // the one that failed provisionally.
            guard let self else { return }
            if let url = self.tabManager.selectedTab?.url {
                self.currentWebView?.load(URLRequest(url: url))
            } else {
                self.currentWebView?.reload()
            }
        }

        let hosting = NSHostingController(rootView: errorView)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.width, .height]
        hosting.view.alphaValue = 0

        view.addSubview(hosting.view, positioned: .below, relativeTo: cornerMaskView)
        errorPageHosting = hosting

        // Animate in
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            hosting.view.animator().alphaValue = 1
        }
    }

    func clearErrorPage() {
        tabManager.selectedTab?.browsingError = nil
        guard let hosting = errorPageHosting else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            hosting.view.animator().alphaValue = 0
        }, completionHandler: {
            DispatchQueue.main.async { hosting.view.removeFromSuperview() }
        })
        errorPageHosting = nil
    }

    func tabForWebView(_ webView: WKWebView) -> BrowserTab? {
        tabManager.tabs.first(where: { $0.webView === webView })
    }

    func openURLInNewTab(_ url: URL) {
        onNewTabRequested?(url)
    }

    // MARK: - Quick Search

    func toggleQuickSearch() {
        guard let overlay = quickSearchOverlay else { return }
        overlay.toggle(in: view, navigateInNewTab: false)
    }

    func showQuickSearch(navigateInNewTab: Bool) {
        guard let overlay = quickSearchOverlay else { return }
        if overlay.isVisible {
            overlay.dismiss()
        } else {
            overlay.show(in: view, navigateInNewTab: navigateInNewTab)
        }
    }

    /// Always presents the quick-search overlay (never toggles). Used by ⌘+T
    /// which creates a new tab and immediately opens search on it — in that
    /// flow toggling-off would be a surprising UX.
    func presentQuickSearch(navigateInNewTab: Bool) {
        guard let overlay = quickSearchOverlay else { return }
        if overlay.isVisible {
            overlay.dismiss()
        }
        overlay.show(in: view, navigateInNewTab: navigateInNewTab)
    }

    func dismissQuickSearch() {
        quickSearchOverlay?.dismiss()
    }

    // MARK: - Find In Page

    func showFindBar() {
        guard findBar == nil else {
            findBar?.focusSearchField()
            return
        }

        let controller = FindInPageController(webView: currentWebView)
        let bar = FindInPageBar(controller: controller)
        bar.onDismiss = { [weak self] in
            self?.hideFindBar()
        }
        findBar = bar
        findController = controller
        view.addSubview(bar)
        layoutFindBar()
        layoutCurrentWebView()
        bar.focusSearchField()
    }

    func hideFindBar() {
        findController?.clearHighlights()
        findBar?.removeFromSuperview()
        findBar = nil
        findController = nil
        layoutCurrentWebView()
    }

    func toggleFindBar() {
        if findBar != nil {
            hideFindBar()
        } else {
            showFindBar()
        }
    }

    func findNext() { findController?.findNext() }
    func findPrevious() { findController?.findPrevious() }

    // MARK: - Save-Password Prompt Observation

    private func observePasswordCoordinator() {
        guard let coordinator = passwordCoordinator else { return }
        Task { @MainActor [weak self] in
            var last: PasswordManagerCoordinator.PendingCredential? = nil
            while !Task.isCancelled {
                guard let self else { return }
                let current = coordinator.pendingSaveCredential
                if current != last {
                    self.applyPendingSaveCredential(current)
                    last = current
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func applyPendingSaveCredential(_ pending: PasswordManagerCoordinator.PendingCredential?) {
        guard let pending else { savePromptOverlay.hide(); return }
        guard let coordinator = passwordCoordinator else { return }

        let promptView: SavePromptView
        let mode: SavePromptView.Mode
        switch pending {
        case let .save(site, username, password):
            mode = .save
            promptView = SavePromptView(
                mode: .save, site: site,
                username: username, password: password,
                onSubmit: { [weak coordinator] u, p in
                    coordinator?.acceptPending(editedUsername: u, editedPassword: p)
                },
                onNever: { [weak coordinator] in coordinator?.declineForever() },
                onClose: { [weak coordinator] in coordinator?.dismissPending() }
            )
        case let .update(site, username, password, _):
            mode = .update
            promptView = SavePromptView(
                mode: .update, site: site,
                username: username, password: password,
                onSubmit: { [weak coordinator] u, p in
                    coordinator?.acceptPending(editedUsername: u, editedPassword: p)
                },
                onNever: { [weak coordinator] in coordinator?.declineForever() },
                onClose: { [weak coordinator] in coordinator?.dismissPending() }
            )
        }
        savePromptOverlay.show(view: promptView, mode: mode)
    }

    // MARK: - Autofill Popover

    private func presentAutofill(rectInDoc: CGRect, credentials: [Credential], form: DetectedForm) {
        guard let webView = currentWebView, let window = webView.window else {
            autofillPanel.hide()
            return
        }
        // 1. CSS px (top-doc, viewport-relative) -> AppKit webView coords.
        //    Y-axis flip: web docs grow down, AppKit grows up.
        let webViewRect = NSRect(
            x: rectInDoc.minX,
            y: webView.bounds.height - rectInDoc.maxY,
            width: rectInDoc.width,
            height: rectInDoc.height
        )
        // 2. webView coords -> window coords.
        let windowRect = webView.convert(webViewRect, to: nil)
        // 3. window coords -> screen coords.
        let screenRect = window.convertToScreen(windowRect)
        autofillPanel.show(below: screenRect, in: window, credentials: credentials) { [weak self] cred in
            self?.fillCredential(cred, into: form)
        }
    }

    private func fillCredential(_ cred: Credential, into form: DetectedForm) {
        guard let webView = currentWebView else { return }
        let payload: [String: Any] = [
            "usernameFieldId": form.usernameFieldId ?? "",
            "username": cred.username,
            "passwordFieldId": form.passwordFieldId,
            "password": cred.password,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("__BrowsePasswordManager.fillCredential(\(json))")
    }

    private func layoutFindBar() {
        guard let fb = findBar else { return }
        let h = Layout.findBarHeight
        let vPadding: CGFloat = 8
        let barWidth: CGFloat = 400
        fb.frame = NSRect(
            x: (view.bounds.width - barWidth) / 2,
            y: view.bounds.height - h - vPadding,
            width: barWidth,
            height: h
        )
    }
}

// MARK: - Corner Mask View

/// Draws the chrome background color into each corner on top of the WKWebView,
/// faking rounded corners. WKWebView's internal compositing layers ignore
/// parent masksToBounds, so this overlay paints over the sharp corners instead.
private final class CornerMaskView: NSView {

    private let maskLayer = CAShapeLayer()
    private let radius: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Fill the corners with chrome color, cut out the rounded rect center
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = Colors.chromeBg.cgColor
        layer?.addSublayer(maskLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // Use the layer-update path so updateLayer() is called on setNeedsDisplay.
    // This lets reapplyTheme() re-read the chrome color after a theme switch
    // (the CAShapeLayer's fillColor otherwise stays cached at the old value).
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        maskLayer.fillColor = Colors.chromeBg.cgColor
    }

    override func layout() {
        super.layout()
        let rect = bounds
        maskLayer.frame = rect

        // Outer path = full rect, inner path = rounded rect (punched out)
        let outer = CGMutablePath()
        outer.addRect(rect)
        outer.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
        maskLayer.path = outer
    }

    // Pass all events through — this is purely visual
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
