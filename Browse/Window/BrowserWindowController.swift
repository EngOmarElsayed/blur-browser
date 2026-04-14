import AppKit
import Observation

@MainActor
final class BrowserWindowController: NSWindowController {

    let tabManager = TabManager()
    let historyStore = HistoryStore()

    private var splitVC: MainSplitViewController!
    private var quickSearchOverlay: QuickSearchOverlay?
    private var observationTask: Task<Void, Never>?

    init() {
        let window = BrowserWindow()
        super.init(window: window)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        splitVC = MainSplitViewController(tabManager: tabManager, historyStore: historyStore)
        splitVC.webViewController.onNewTabRequested = { [weak self] url in
            self?.tabManager.addNewTab(url: url)
        }
        splitVC.webViewController.setHistoryStore(historyStore)

        // Create the quick search overlay and hand it to the web view controller
        let overlay = QuickSearchOverlay(tabManager: tabManager, historyStore: historyStore)
        quickSearchOverlay = overlay
        splitVC.webViewController.setQuickSearchOverlay(overlay)

        window?.contentViewController = splitVC

        // Observe selected tab changes and URL changes to update web view and address bar
        observationTask = Task { [weak self] in
            guard let self else { return }
            var lastID: UUID?
            var lastURL: URL?
            while !Task.isCancelled {
                let currentID = tabManager.selectedTabID
                let currentURL = tabManager.selectedTab?.url

                if currentID != lastID {
                    lastID = currentID
                    lastURL = currentURL
                    splitVC.webViewController.displayTab(tabManager.selectedTab)
                    splitVC.addressBar.updateForTab(tabManager.selectedTab)
                } else if currentURL != lastURL {
                    lastURL = currentURL
                    splitVC.addressBar.updateForTab(tabManager.selectedTab)
                }

                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Actions forwarded from AppDelegate

    func openQuickSearch() {
        splitVC.webViewController.toggleQuickSearch()
    }

    func newTabAndSearch() {
        splitVC.webViewController.showQuickSearch(navigateInNewTab: true)
    }

    func focusAndSelectURLBar() {
        splitVC.addressBar.focusAndSelectAll()
    }

    func copyCurrentURL() {
        guard let url = tabManager.selectedTab?.url?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    func closeCurrentTab() {
        guard let tab = tabManager.selectedTab else { return }
        tabManager.closeTab(tab)
    }

    func toggleSidebar() {
        splitVC.toggleSidebar()
    }

    func toggleFindInPage() {
        splitVC.webViewController.toggleFindBar()
    }

    func findNext() {
        splitVC.webViewController.findNext()
    }

    func findPrevious() {
        splitVC.webViewController.findPrevious()
    }

    func goBack() {
        splitVC.webViewController.goBack()
    }

    func goForward() {
        splitVC.webViewController.goForward()
    }

    func reloadPage(bypassCache: Bool) {
        splitVC.webViewController.reload(bypassCache: bypassCache)
    }

    func toggleHistory() {
        splitVC.toggleHistoryMode()
    }

    func nextTab() {
        tabManager.selectNextTab()
    }

    func previousTab() {
        tabManager.selectPreviousTab()
    }

    func selectTab(at index: Int) {
        tabManager.selectTab(at: index)
    }
}
