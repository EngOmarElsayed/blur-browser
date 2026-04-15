import AppKit
import WebKit

@MainActor
final class WebViewController: NSViewController {

    private let tabManager: TabManager
    private let coordinator = WebViewCoordinator()
    private var currentWebView: WKWebView?
    private var findBar: FindInPageBar?
    private var findController: FindInPageController?
    private var historyStore: HistoryStore?
    private var quickSearchOverlay: QuickSearchOverlay?

    var onNewTabRequested: ((URL) -> Void)?

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
        coordinator.viewController = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private let cornerMaskView = CornerMaskView()

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

    func displayTab(_ tab: BrowserTab?) {
        // Unregister message handlers from the old web view
        if let oldWV = currentWebView {
            coordinator.unregisterMessageHandlers(on: oldWV)
        }

        // Remove old web view
        currentWebView?.removeFromSuperview()
        findBar?.removeFromSuperview()

        guard let tab else {
            currentWebView = nil
            return
        }

        let wv = tab.webView
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator

        // Register content filter message handlers
        coordinator.resetFilterState()
        coordinator.registerMessageHandlers(on: wv)

        wv.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(wv)
        currentWebView = wv

        // Corner mask on top of web view to fake rounded corners
        cornerMaskView.removeFromSuperview()
        view.addSubview(cornerMaskView)

        layoutCurrentWebView()

        if let fb = findBar {
            view.addSubview(fb)
            layoutFindBar()
        }
    }

    private func layoutCurrentWebView() {
        guard let wv = currentWebView else { return }
        wv.frame = view.bounds
        cornerMaskView.frame = view.bounds
        // Keep corner mask above web view
        view.addSubview(cornerMaskView, positioned: .above, relativeTo: wv)
    }

    // MARK: - Navigation

    func goBack() { currentWebView?.goBack() }
    func goForward() { currentWebView?.goForward() }

    func reload(bypassCache: Bool) {
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

        dialog.onSubmit = { username, password in
            completion(username, password)
        }

        dialog.onCancel = {
            completion(nil, nil)
        }

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

    func onNavigationFinished() {
        guard let tab = tabManager.selectedTab, let url = tab.url else { return }
        historyStore?.addEntry(url: url, title: tab.title)
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
    private let radius: CGFloat = 8

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
