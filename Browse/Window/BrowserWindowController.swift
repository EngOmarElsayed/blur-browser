import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {

    let tabManager = TabManager()
    let historyStore = HistoryStore()
    let downloadStore = DownloadStore()
    private(set) var downloadManager: DownloadManager!

    private var splitVC: MainSplitViewController!
    private var quickSearchOverlay: QuickSearchOverlay?
    private var observationTask: Task<Void, Never>?

    /// The tab ID the polling loop last observed. Promoted from a local var so
    /// newTabAndSearch can pre-advance it and prevent the polling from firing
    /// a redundant displayTab pass that would dismiss the just-shown overlay.
    private var lastObservedTabID: UUID?

    init() {
        let window = BrowserWindow()
        super.init(window: window)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        window?.delegate = self

        // Restore unpinned tabs from JSON session if enabled
        if SettingsStore.shared.restoreTabsOnLaunch {
            TabSessionStore.restore(into: tabManager)
        }

        // Restore pinned tabs from SwiftData (always, after JSON restore so they aren't wiped)
        tabManager.restorePinnedTabs()

        downloadManager = DownloadManager(store: downloadStore)

        splitVC = MainSplitViewController(
            tabManager: tabManager,
            historyStore: historyStore,
            downloadStore: downloadStore,
            downloadManager: downloadManager
        )
        splitVC.webViewController.onNewTabRequested = { [weak self] url in
            self?.tabManager.addNewTab(url: url)
        }
        splitVC.webViewController.setHistoryStore(historyStore)
        // DownloadManager needs the WebViewController to present the confirmation alert
        downloadManager.webViewController = splitVC.webViewController
        // WebViewController needs to know the DownloadManager so WebViewCoordinator can hand off
        splitVC.webViewController.setDownloadManager(downloadManager)

        // Create the quick search overlay and hand it to the web view controller
        let overlay = QuickSearchOverlay(tabManager: tabManager, historyStore: historyStore)
        quickSearchOverlay = overlay
        splitVC.webViewController.setQuickSearchOverlay(overlay)

        window?.contentViewController = splitVC

        // Prevent the address bar from auto-focusing on launch.
        // Setting initialFirstResponder to the plain content view means AppKit
        // won't walk the key view loop and land on the URL text field when the
        // window becomes key.
        window?.initialFirstResponder = splitVC.view

        // Defensive: clear focus once the window actually becomes key.
        // Use a weak ref so we don't leak.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak window, weak splitVC] _ in
            guard let window, let splitView = splitVC?.view else { return }
            // If the first responder is a text field's field editor, clear it
            if window.firstResponder is NSText {
                window.makeFirstResponder(splitView)
            }
        }

        // Observe selected tab changes, URL changes, and loading progress
        observationTask = Task { [weak self] in
            guard let self else { return }
            var lastURL: URL?
            var lastProgress: Double = 0
            var lastLoading: Bool = false
            var lastDownloadSignature: String = ""
            var lastThemeID: ThemeID? = ThemeStore.shared.currentThemeID
            while !Task.isCancelled {
                // Theme change detection
                let currentThemeID = ThemeStore.shared.currentThemeID
                if currentThemeID != lastThemeID {
                    lastThemeID = currentThemeID
                    (window as? BrowserWindow)?.applyActiveTheme()
                    splitVC.reapplyTheme()
                    splitVC.addressBar.applyActiveTheme()
                    splitVC.addressBar.updateForTab(tabManager.selectedTab)

                    // Propagate color scheme + re-pick wallpapers for new-tab tabs
                    // so the wallpaper reflects the newly selected theme.
                    let newWallpapers = ThemeStore.shared.current.wallpaperNames
                    for tab in tabManager.tabs {
                        BrowserTab.syncColorScheme(tab.webView)
                        if tab.url == AppConstants.newTabURL {
                            tab.newTabWallpaperName = newWallpapers.randomElement()
                        }
                    }
                    splitVC.webViewController.refreshNewTabOverlay()
                }
                let currentID = tabManager.selectedTabID
                let currentURL = tabManager.selectedTab?.url
                let currentProgress = tabManager.selectedTab?.estimatedProgress ?? 0
                let currentLoading = tabManager.selectedTab?.isLoading ?? false

                // Signature that changes when download state changes (active count,
                // per-item progress, status transitions)
                let downloadSig = downloadStore.items.map { "\($0.id):\($0.statusRaw):\($0.completedBytes)" }.joined(separator: ",")
                if downloadSig != lastDownloadSignature {
                    lastDownloadSignature = downloadSig
                    splitVC.refreshDownloadsToast()
                }

                if currentID != lastObservedTabID {
                    lastObservedTabID = currentID
                    lastURL = currentURL
                    lastProgress = currentProgress
                    lastLoading = currentLoading
                    // Dismiss quick search when switching tabs — it's a per-tab
                    // intent, not a persistent overlay.
                    splitVC.webViewController.dismissQuickSearch()
                    splitVC.webViewController.displayTab(tabManager.selectedTab)
                    splitVC.addressBar.updateForTab(tabManager.selectedTab)
                    splitVC.syncReaderModeForSelectedTab()
                } else if currentURL != lastURL {
                    lastURL = currentURL
                    splitVC.addressBar.updateForTab(tabManager.selectedTab)
                    // URL change can mean: user navigated from new-tab to a real
                    // URL, or back to the new-tab. Refresh the wallpaper overlay.
                    splitVC.webViewController.refreshNewTabOverlay()
                } else if currentProgress != lastProgress || currentLoading != lastLoading {
                    lastProgress = currentProgress
                    lastLoading = currentLoading
                    splitVC.addressBar.updateProgress(currentProgress, isLoading: currentLoading)
                }

                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - NSWindowDelegate

    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            TabSessionStore.save(tabManager: tabManager)
        }
    }

    // MARK: - Actions forwarded from AppDelegate

    func openQuickSearch() {
        splitVC.webViewController.toggleQuickSearch()
    }

    func newTabAndSearch() {
        // Create a new blur://newtab tab and immediately open quick search
        // on it. Quick search submit navigates the current tab (the new one),
        // not yet-another-new-tab.
        tabManager.addNewTab()
        // Pre-advance the observer so the polling task's tab-switch branch
        // doesn't fire a redundant displayTab (which would dismiss the overlay
        // we're about to show).
        lastObservedTabID = tabManager.selectedTabID
        splitVC.webViewController.displayTab(tabManager.selectedTab)
        splitVC.addressBar.updateForTab(tabManager.selectedTab)
        splitVC.webViewController.presentQuickSearch(navigateInNewTab: false)
    }

    func focusAndSelectURLBar() {
        splitVC.addressBar.focusAndSelectAll()
    }

    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.html, .xml, .plainText, .pdf]
        panel.message = "Choose a file to open"
        panel.prompt = "Open"
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.tabManager.addNewTab(url: url)
            }
        }
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

    func focusMode() {
        splitVC.focusMode()
    }

    func toggleAddressBar() {
        splitVC.toggleAddressBar()
    }

    func toggleReaderMode() {
        splitVC.toggleReaderMode()
    }

    func showDownloadsInSidebar() {
        splitVC.showDownloadsInSidebar()
    }

    func toggleShortcutsOverlay() {
        splitVC.toggleShortcutsOverlay()
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

    private var isInspectorOpen = false

    func toggleInspector() {
        guard let webView = tabManager.selectedTab?.webView else { return }
        webView.isInspectable = true
        guard let inspector = webView.perform(Selector(("_inspector")))?.takeUnretainedValue() else { return }

        if isInspectorOpen {
            _ = inspector.perform(#selector(NSRunningApplication.hide))
            isInspectorOpen = false
        } else {
            _ = inspector.perform(Selector(("show")))
            isInspectorOpen = true
        }
    }
}
