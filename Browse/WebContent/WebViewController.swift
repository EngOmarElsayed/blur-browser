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

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Colors.surfacePrimary.cgColor
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
        coordinator.observe(wv, for: tab)

        // Register content filter message handlers
        coordinator.resetFilterState()
        coordinator.registerMessageHandlers(on: wv)

        wv.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(wv)
        currentWebView = wv

        layoutCurrentWebView()

        if let fb = findBar {
            view.addSubview(fb)
            layoutFindBar()
        }
    }

    private func layoutCurrentWebView() {
        guard let wv = currentWebView else { return }
        wv.frame = view.bounds
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
        let hPadding: CGFloat = 8
        let vPadding: CGFloat = 6
        let barWidth: CGFloat = 400
        fb.frame = NSRect(
            x: view.bounds.width - barWidth - hPadding,
            y: view.bounds.height - h - vPadding,
            width: barWidth,
            height: h
        )
    }
}
