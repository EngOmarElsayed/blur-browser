import AppKit
import SwiftUI

@MainActor
final class MainSplitViewController: NSViewController {

    let tabManager: TabManager
    let historyStore: HistoryStore
    let downloadStore: DownloadStore
    let downloadManager: DownloadManager
    let webViewController: WebViewController
    let addressBar: AddressBarViewController

    private var sidebarVC: SidebarViewController!
    private var historyHostingVC: NSHostingController<HistoryPanelView>!
    private let leftDividerView = ResizeDividerView()
    private let rightDividerView = ResizeDividerView()
    private let borderOverlay = WindowBorderOverlayView()

    private var sidebarWidth: CGFloat = Layout.sidebarDefaultWidth
    private var historyPanelWidth: CGFloat = 300
    private var isSidebarCollapsed = false
    private var isHistoryCollapsed = true
    private(set) var isAddressBarHidden = false
    private var isAddressBarTemporarilyShown = false
    private var toolbarView: NSView!
    private let contentContainerView = NSView()
    private let sidebarToggleButton = NSButton()
    private let topHoverZone = HoverDetectorView()
    private var hideTimer: Timer?
    private var readerOverlay: ReaderModeView?
    private var readerDimView: GaussianBlurView?
    private var readerDimTopConstraint: NSLayoutConstraint?
    private var shortcutsOverlayHosting: NSHostingController<ShortcutsOverlayView>?
    private var shortcutsDimView: GaussianBlurView?
    private var shortcutsKeyMonitor: Any?
    private var downloadsToastHosting: NSHostingController<DownloadsToastView>?
    private var downloadsToastAutoDismissTask: Task<Void, Never>?
    /// IDs of downloads currently visible in the toast. Includes in-progress,
    /// paused, and recently-finished downloads until the user dismisses them.
    private var toastVisibleIDs: Set<UUID> = []
    /// IDs we've already tracked at least once for the toast — used so that
    /// dismissing an in-progress item doesn't immediately re-add it on the next
    /// refresh. Only brand-new downloads get auto-added.
    private var toastKnownIDs: Set<UUID> = []

    /// Blur radius for the reader-mode dim (live CAFilter Gaussian blur).
    /// Tune this to taste.
    private let readerBlurRadius: CGFloat = 8

    init(
        tabManager: TabManager,
        historyStore: HistoryStore,
        downloadStore: DownloadStore,
        downloadManager: DownloadManager
    ) {
        self.tabManager = tabManager
        self.historyStore = historyStore
        self.downloadStore = downloadStore
        self.downloadManager = downloadManager
        self.webViewController = WebViewController(tabManager: tabManager)
        self.addressBar = AddressBarViewController(tabManager: tabManager)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.wantsLayer = true
        view.layer?.backgroundColor = Colors.chromeBg.cgColor
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // -- Content container (toolbar + web view) with rounded corners --
        contentContainerView.wantsLayer = true
        contentContainerView.layer?.cornerRadius = 16
        contentContainerView.layer?.masksToBounds = true
        view.addSubview(contentContainerView)

        // -- Toolbar --
        addressBar.onToggleSidebar = { [weak self] in
            self?.toggleSidebar()
        }
        addressBar.onToggleAddressBar = { [weak self] in
            self?.focusMode()
        }
        addressBar.onToggleReaderMode = { [weak self] in
            self?.toggleReaderMode()
        }
        webViewController.onReaderAvailabilityChanged = { [weak self] available in
            self?.addressBar.setReaderAvailable(available)
        }
        toolbarView = makeToolbarView()
        contentContainerView.addSubview(toolbarView)

        // -- Web content --
        addChild(webViewController)
        contentContainerView.addSubview(webViewController.view)

        // -- Left sidebar --
        sidebarVC = SidebarViewController(
            tabManager: tabManager,
            historyStore: historyStore,
            downloadStore: downloadStore
        )
        sidebarVC.onToggleHistory = { [weak self] in
            self?.toggleHistoryMode()
        }
        sidebarVC.onCancelDownload = { [weak self] id in
            self?.downloadManager.cancelDownload(id: id)
        }
        sidebarVC.onPauseDownload = { [weak self] id in
            self?.downloadManager.pauseDownload(id: id)
        }
        sidebarVC.onResumeDownload = { [weak self] id in
            guard let self, let webView = self.tabManager.selectedTab?.webView else { return }
            self.downloadManager.resumeDownload(id: id, using: webView)
        }
        addChild(sidebarVC)
        view.addSubview(sidebarVC.view)

        // -- Sidebar toggle button --
        sidebarToggleButton.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
        sidebarToggleButton.isBordered = false
        sidebarToggleButton.bezelStyle = .accessoryBarAction
        sidebarToggleButton.contentTintColor = Colors.foregroundMuted
        sidebarToggleButton.target = self
        sidebarToggleButton.action = #selector(sidebarToggleTapped)
        view.addSubview(sidebarToggleButton)

        // -- Right history panel (created once, starts hidden) --
        let panelView = HistoryPanelView(
            historyStore: historyStore,
            tabManager: tabManager,
            onDismiss: { [weak self] in
                self?.toggleHistoryMode()
            }
        )
        historyHostingVC = NSHostingController(rootView: panelView)
        historyHostingVC.sizingOptions = []
        historyHostingVC.view.wantsLayer = true
        historyHostingVC.view.layer?.backgroundColor = Colors.chromeBg.cgColor
        addChild(historyHostingVC)
        view.addSubview(historyHostingVC.view)
        historyHostingVC.view.isHidden = true

        // -- Dividers --
        view.addSubview(leftDividerView)
        let leftPan = NSPanGestureRecognizer(target: self, action: #selector(handleLeftDividerDrag(_:)))
        leftDividerView.addGestureRecognizer(leftPan)

        rightDividerView.isHidden = true
        view.addSubview(rightDividerView)
        let rightPan = NSPanGestureRecognizer(target: self, action: #selector(handleRightDividerDrag(_:)))
        rightDividerView.addGestureRecognizer(rightPan)

        // -- Top hover zone for auto-showing address bar --
        topHoverZone.onMouseEntered = { [weak self] in
            self?.handleTopHoverEntered()
        }
        topHoverZone.onMouseExited = { [weak self] in
            self?.handleTopHoverExited()
        }
        view.addSubview(topHoverZone)

        // -- Arc-style border overlay (topmost, non-interactive) --
        view.addSubview(borderOverlay)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layoutSubviews()
    }

    private func layoutSubviews() {
        let bounds = view.bounds
        let toolbarHeight = Layout.toolbarHeight
        let dividerHitWidth: CGFloat = 16
        // Chrome padding — visible on right and bottom edges (left is sidebar, top is toolbar)
        let chromeEdge: CGFloat = 8

        // In full screen, the safe area top inset is 0 (no titlebar).
        // In windowed mode with fullSizeContentView, the titlebar occupies space at the top.
        let topInset: CGFloat = view.safeAreaInsets.top

        // ── Left sidebar ──
        let effectiveSidebarWidth = isSidebarCollapsed ? 0 : sidebarWidth

        sidebarVC.view.frame = NSRect(
            x: 0,
            y: chromeEdge,
            width: effectiveSidebarWidth,
            height: bounds.height - chromeEdge - topInset
        )
        sidebarVC.view.isHidden = isSidebarCollapsed

        // Sidebar toggle button
        let _: CGFloat = 28
        let trafficLightCenterY: CGFloat
        if let closeButton = view.window?.standardWindowButton(.closeButton) {
            let closeFrame = closeButton.convert(closeButton.bounds, to: view)
            trafficLightCenterY = closeFrame.midY
        } else {
            trafficLightCenterY = bounds.height - 14
        }
        // Sidebar toggle is now in the address bar — hide this one
        sidebarToggleButton.isHidden = true

        // Hide traffic light buttons when both sidebar and address bar are hidden (and not temporarily shown)
        let hideTrafficLights = isSidebarCollapsed && isAddressBarHidden && !isAddressBarTemporarilyShown
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            view.window?.standardWindowButton(buttonType)?.isHidden = hideTrafficLights
        }

        // Left divider (between sidebar and web content only)
        leftDividerView.frame = NSRect(
            x: effectiveSidebarWidth - (dividerHitWidth - 1) / 2,
            y: chromeEdge, width: dividerHitWidth,
            height: bounds.height
        )
        leftDividerView.isHidden = true
        view.addSubview(leftDividerView, positioned: .above, relativeTo: contentContainerView)

        let contentX = isSidebarCollapsed ? chromeEdge : effectiveSidebarWidth

        // ── Right history panel ──
        let effectiveHistoryWidth = isHistoryCollapsed ? 0 : historyPanelWidth

        historyHostingVC.view.isHidden = isHistoryCollapsed
        historyHostingVC.view.frame = NSRect(
            x: bounds.width - effectiveHistoryWidth - chromeEdge,
            y: chromeEdge,
            width: effectiveHistoryWidth,
            height: bounds.height - chromeEdge
        )

        // Right divider
        rightDividerView.isHidden = isHistoryCollapsed
        if !isHistoryCollapsed {
            rightDividerView.frame = NSRect(
                x: bounds.width - effectiveHistoryWidth - chromeEdge - (dividerHitWidth - 1) / 2,
                y: chromeEdge, width: dividerHitWidth,
                height: bounds.height - chromeEdge
            )
            view.addSubview(rightDividerView, positioned: .above, relativeTo: historyHostingVC.view)
        }

        // ── Content container (toolbar + web view) ──
        let contentRight = isHistoryCollapsed ? chromeEdge : effectiveHistoryWidth + chromeEdge + 1
        let fullContentWidth = bounds.width - contentX - contentRight

        // The toolbar is effectively visible if it's not hidden OR temporarily shown on hover
        let isToolbarVisible = !isAddressBarHidden || isAddressBarTemporarilyShown
        let topChromeEdge: CGFloat = isToolbarVisible ? 0 : chromeEdge
        let containerHeight = bounds.height - chromeEdge - topChromeEdge

        contentContainerView.frame = NSRect(
            x: contentX,
            y: chromeEdge,
            width: fullContentWidth,
            height: containerHeight
        )

        // Toolbar at top of container
        toolbarView.isHidden = !isToolbarVisible
        let effectiveToolbarHeight: CGFloat = isToolbarVisible ? toolbarHeight : 0

        // Top hover zone — invisible strip at the top of the window to detect mouse
        let hoverZoneHeight: CGFloat = 10
        topHoverZone.frame = NSRect(
            x: 0,
            y: bounds.height - hoverZoneHeight,
            width: bounds.width,
            height: hoverZoneHeight
        )
        // Only active when the address bar is permanently hidden and not temporarily shown
        topHoverZone.isHidden = !isAddressBarHidden || isAddressBarTemporarilyShown
        view.addSubview(topHoverZone, positioned: .above, relativeTo: borderOverlay)
        toolbarView.frame = NSRect(
            x: 0,
            y: containerHeight - toolbarHeight,
            width: fullContentWidth,
            height: toolbarHeight
        )

        // Web content fills remainder below toolbar (or full height when toolbar hidden)
        let webHeight = containerHeight - effectiveToolbarHeight
        webViewController.view.frame = NSRect(
            x: 0, y: 0,
            width: fullContentWidth,
            height: webHeight
        )

        // Border overlay always on top, covering full bounds
        borderOverlay.frame = bounds
        view.addSubview(borderOverlay, positioned: .above, relativeTo: nil)

        // Keep the reader dim view's top inset in sync with the address bar
        updateReaderDimTopInset()
    }

    private func makeToolbarView() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = .clear

        addChild(addressBar)
        addressBar.view.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(addressBar.view)

        let constraints = [
            addressBar.view.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            addressBar.view.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            addressBar.view.topAnchor.constraint(equalTo: bar.topAnchor),
            addressBar.view.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ]
        constraints.forEach { $0.priority = .init(999) }
        NSLayoutConstraint.activate(constraints)

        return bar
    }

    // MARK: - Actions

    @objc private func sidebarToggleTapped() {
        toggleSidebar()
    }

    func toggleSidebar() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            isSidebarCollapsed.toggle()
            addressBar.setSidebarCollapsed(isSidebarCollapsed)
            layoutSubviews()
        }
    }

    func toggleAddressBar() {
        if isAddressBarTemporarilyShown {
            isAddressBarTemporarilyShown = false
        }
        hideTimer?.invalidate()
        hideTimer = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            isAddressBarHidden.toggle()
            layoutSubviews()
        }
    }

    func focusMode() {
        // If we're dismisp sing a temporary reveal, just clear the temp state
        if isAddressBarTemporarilyShown {
            isAddressBarTemporarilyShown = false
        }
        hideTimer?.invalidate()
        hideTimer = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            isAddressBarHidden = true

            isSidebarCollapsed = true
            addressBar.setSidebarCollapsed(isSidebarCollapsed)

            layoutSubviews()
        }
    }

    // MARK: - Top Hover Auto-Reveal

    private func handleTopHoverEntered() {
        guard isAddressBarHidden, !isAddressBarTemporarilyShown else { return }
        hideTimer?.invalidate()
        hideTimer = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            isAddressBarTemporarilyShown = true
            layoutSubviews()
        }
    }

    private func handleTopHoverExited() {
        guard isAddressBarTemporarilyShown else { return }
        // Small delay before hiding so the user can move into the toolbar
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissTemporaryAddressBar()
            }
        }
    }

    private func dismissTemporaryAddressBar() {
        guard isAddressBarTemporarilyShown else { return }
        // Check if mouse is still in the toolbar area
        if let window = view.window {
            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            let mouseInView = view.convert(mouseInWindow, from: nil)
            let toolbarFrame = toolbarView.convert(toolbarView.bounds, to: view)
            let expandedFrame = NSRect(
                x: toolbarFrame.origin.x,
                y: toolbarFrame.origin.y,
                width: toolbarFrame.width,
                height: toolbarFrame.height + 10
            )
            if expandedFrame.contains(mouseInView) {
                hideTimer?.invalidate()
                hideTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.dismissTemporaryAddressBar()
                    }
                }
                return
            }
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            isAddressBarTemporarilyShown = false
            layoutSubviews()
        }
    }

    func toggleHistoryMode() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            isHistoryCollapsed.toggle()
            layoutSubviews()
        }
    }

    // MARK: - Sidebar Mode

    /// Toggle the sidebar between Tabs and Downloads. Auto-expands the sidebar
    /// if it's currently collapsed so the list is actually visible.
    func showDownloadsInSidebar() {
        if isSidebarCollapsed {
            toggleSidebar()
        }
        sidebarVC.toggleDownloads()
    }

    // MARK: - Reader Mode

    func toggleReaderMode() {
        Task {
            guard let tab = tabManager.selectedTab else { return }
            let isReaderable = await ReaderModeService.isReaderable(webView: tab.webView)
            guard isReaderable else {
                NSSound.beep()
                return
            }

            if tab.readerArticle != nil {
                // Reader is active for this tab — dismiss it and clear tab state
                tab.readerArticle = nil
                tab.readerParsedForURL = nil
                unmountReaderOverlay(animated: true)
                addressBar.setReaderActive(false)
            } else {
                // Reader is off — parse and enable
                await enableReaderMode(on: tab)
            }
        }
    }

    /// Parses the article for the given tab, stores it on the tab, and mounts
    /// the overlay if the tab is still selected when parsing completes.
    private func enableReaderMode(on tab: BrowserTab) async {
        guard let article = await ReaderModeService.parseArticle(webView: tab.webView) else {
            print("[ReaderMode] Failed to parse article for reader mode")
            NSSound.beep()
            return
        }

        tab.readerArticle = article
        tab.readerParsedForURL = tab.url

        // If the user switched away while parsing, don't mount — the overlay
        // will reappear when they switch back.
        guard tabManager.selectedTab === tab else { return }
        mountReaderOverlay(for: article, animated: true)
        addressBar.setReaderActive(true)
    }

    /// Mounts the reader overlay for the currently selected tab.
    /// Caller must ensure the selected tab has a cached `readerArticle`.
    private func mountReaderOverlay(for article: ReaderArticle, animated: Bool) {
        // If an overlay already exists (e.g., stale from previous tab), tear it down first.
        unmountReaderOverlay(animated: false)

        // Reader overlay sits inside the content container, offset down by the
        // toolbar height so it only covers the web page area (not the address bar).
        let host = contentContainerView
        let toolbarInset = isAddressBarHidden && !isAddressBarTemporarilyShown ? 0 : Layout.toolbarHeight

        // Dim background — live Gaussian blur (CAFilter private API) matching
        // the "Blur" browser name. Blurs the web page content in real time.
        let dim = GaussianBlurView(radius: readerBlurRadius)
        dim.wantsLayer = true
        dim.layer?.cornerRadius = 8
        dim.layer?.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
        dim.layer?.masksToBounds = true
        dim.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(dim, positioned: .above, relativeTo: nil)
        let topConstraint = dim.topAnchor.constraint(equalTo: host.topAnchor, constant: CGFloat(toolbarInset))
        NSLayoutConstraint.activate([
            dim.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            topConstraint,
            dim.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        readerDimView = dim
        readerDimTopConstraint = topConstraint

        // Dismiss on clicking outside the reader panel
        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(readerDimClicked))
        dim.addGestureRecognizer(clickRecognizer)

        let overlay = ReaderModeView(article: article, baseURL: tabManager.selectedTab?.url)
        overlay.onClose = { [weak self] in
            self?.dismissReaderMode()
        }
        overlay.onLinkClicked = { [weak self] url in
            // Open the link in a new selected tab. The reader stays active on
            // the original tab so the user can return to it.
            self?.tabManager.addNewTab(url: url)
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(overlay, positioned: .above, relativeTo: dim)

        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: dim.centerXAnchor),
            overlay.centerYAnchor.constraint(equalTo: dim.centerYAnchor),
            overlay.widthAnchor.constraint(lessThanOrEqualTo: dim.widthAnchor, constant: -40),
            overlay.heightAnchor.constraint(lessThanOrEqualTo: dim.heightAnchor, constant: -40),
            overlay.widthAnchor.constraint(equalToConstant: ReaderModeView.panelWidth),
            overlay.heightAnchor.constraint(equalToConstant: ReaderModeView.panelHeight),
        ])

        if animated {
            overlay.alphaValue = 0
            dim.alphaValue = 0
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                overlay.animator().alphaValue = 1
                dim.animator().alphaValue = 1
            }, completionHandler: nil)
        } else {
            overlay.alphaValue = 1
            dim.alphaValue = 1
        }

        readerOverlay = overlay
    }

    /// Removes the reader overlay from the view hierarchy without touching any
    /// tab's reader state. Use when hiding the overlay for a tab switch.
    private func unmountReaderOverlay(animated: Bool) {
        guard let overlay = readerOverlay else { return }
        let dim = readerDimView
        readerOverlay = nil
        readerDimView = nil
        readerDimTopConstraint = nil

        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                overlay.animator().alphaValue = 0
                dim?.animator().alphaValue = 0
            }, completionHandler: {
                overlay.removeFromSuperview()
                dim?.removeFromSuperview()
            })
        } else {
            overlay.removeFromSuperview()
            dim?.removeFromSuperview()
        }
    }

    /// Keep the reader dim view's top inset in sync with the address bar's
    /// current visibility (focus mode, toggle, hover reveal).
    private func updateReaderDimTopInset() {
        guard let topConstraint = readerDimTopConstraint else { return }
        let toolbarInset: CGFloat = (isAddressBarHidden && !isAddressBarTemporarilyShown)
            ? 0
            : Layout.toolbarHeight
        topConstraint.constant = toolbarInset
    }

    @objc private func readerDimClicked() {
        dismissReaderMode()
    }

    /// User-initiated dismissal (X / ESC / click outside). Clears the tab's
    /// reader state and unmounts the overlay.
    private func dismissReaderMode() {
        if let tab = tabManager.selectedTab {
            tab.readerArticle = nil
            tab.readerParsedForURL = nil
        }
        unmountReaderOverlay(animated: true)
        addressBar.setReaderActive(false)
    }

    /// Called when the selected tab changes. Hides any overlay from the old
    /// tab and shows the cached one on the new tab if reader was active there.
    func syncReaderModeForSelectedTab() {
        guard let tab = tabManager.selectedTab else {
            unmountReaderOverlay(animated: false)
            addressBar.setReaderActive(false)
            return
        }

        // Invalidate cache if the tab has navigated away from the parsed URL
        if let parsedURL = tab.readerParsedForURL, parsedURL != tab.url {
            tab.readerArticle = nil
            tab.readerParsedForURL = nil
        }

        if let article = tab.readerArticle {
            mountReaderOverlay(for: article, animated: false)
            addressBar.setReaderActive(true)
        } else {
            unmountReaderOverlay(animated: false)
            addressBar.setReaderActive(false)
        }
    }

    // MARK: - Downloads Toast

    /// Call whenever download state changes — mounts/dismisses the toast as needed.
    func refreshDownloadsToast() {
        // Auto-add only BRAND-NEW downloads (never seen before). If the user
        // dismissed an in-progress one earlier, it stays dismissed.
        let storeIDs = Set(downloadStore.items.map(\.id))
        for item in downloadStore.items {
            if !toastKnownIDs.contains(item.id) {
                toastKnownIDs.insert(item.id)
                if item.status == .inProgress || item.status == .paused {
                    toastVisibleIDs.insert(item.id)
                }
            }
        }
        // Drop IDs for downloads that no longer exist in the store (e.g. removed
        // from the sidebar downloads panel).
        toastKnownIDs.formIntersection(storeIDs)
        toastVisibleIDs.formIntersection(storeIDs)

        // Build the list of items to show in their original store order
        let visibleItems = downloadStore.items.filter { toastVisibleIDs.contains($0.id) }

        if visibleItems.isEmpty {
            dismissDownloadsToast()
            return
        }

        presentOrUpdateDownloadsToast(items: visibleItems)

        // Auto-dismiss only when ALL items have reached a terminal state
        // (completed/failed/cancelled) — not while there's still anything in-progress/paused.
        let hasActive = visibleItems.contains(where: { $0.status == .inProgress || $0.status == .paused })
        if hasActive {
            downloadsToastAutoDismissTask?.cancel()
            downloadsToastAutoDismissTask = nil
        } else {
            downloadsToastAutoDismissTask?.cancel()
            downloadsToastAutoDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.toastVisibleIDs.removeAll()
                    self?.dismissDownloadsToast()
                }
            }
        }
    }

    private func presentOrUpdateDownloadsToast(items: [DownloadItem]) {
        let toastView = DownloadsToastView(
            items: items,
            onDismiss: { [weak self] in
                // Hide the whole toast window. All currently-visible items stay
                // in toastKnownIDs so they won't be re-added on subsequent refreshes;
                // only BRAND-NEW downloads will re-open the toast.
                guard let self else { return }
                self.toastVisibleIDs.removeAll()
                self.downloadsToastAutoDismissTask?.cancel()
                self.downloadsToastAutoDismissTask = nil
                self.dismissDownloadsToast()
            },
            onCancel: { [weak self] id in
                self?.downloadManager.cancelDownload(id: id)
                // Keep in the toast briefly so the user sees the "Cancelled" state.
                self?.refreshDownloadsToast()
            },
            onPause: { [weak self] id in
                self?.downloadManager.pauseDownload(id: id)
                self?.refreshDownloadsToast()
            },
            onResume: { [weak self] id in
                guard let self, let webView = self.tabManager.selectedTab?.webView else { return }
                self.downloadManager.resumeDownload(id: id, using: webView)
                self.refreshDownloadsToast()
            },
            onReveal: { url in
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        )

        if let existing = downloadsToastHosting {
            existing.rootView = toastView
            return
        }

        let hosting = NSHostingController(rootView: toastView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainerView.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.trailingAnchor.constraint(equalTo: contentContainerView.trailingAnchor, constant: -20),
            hosting.view.bottomAnchor.constraint(equalTo: contentContainerView.bottomAnchor, constant: -20),
        ])

        downloadsToastHosting = hosting

        // Animate in — slide from right + fade
        hosting.view.alphaValue = 0
        hosting.view.layer?.transform = CATransform3DMakeTranslation(20, 0, 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            hosting.view.animator().alphaValue = 1
            hosting.view.layer?.transform = CATransform3DIdentity
        }, completionHandler: nil)
    }

    private func dismissDownloadsToast() {
        guard let hosting = downloadsToastHosting else { return }
        downloadsToastHosting = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            hosting.view.animator().alphaValue = 0
        }, completionHandler: {
            hosting.view.removeFromSuperview()
        })
    }

    // MARK: - Keyboard Shortcuts Cheat Sheet

    func toggleShortcutsOverlay() {
        if shortcutsOverlayHosting != nil {
            dismissShortcutsOverlay()
        } else {
            presentShortcutsOverlay()
        }
    }

    private func presentShortcutsOverlay() {
        // Live Gaussian blur background (same as reader mode) — click to dismiss
        let dim = GaussianBlurView(radius: readerBlurRadius)
        dim.wantsLayer = true
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dim.topAnchor.constraint(equalTo: view.topAnchor),
            dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let click = NSClickGestureRecognizer(target: self, action: #selector(shortcutsDimClicked))
        dim.addGestureRecognizer(click)
        shortcutsDimView = dim

        // SwiftUI panel
        let swiftUIView = ShortcutsOverlayView { [weak self] in
            self?.dismissShortcutsOverlay()
        }
        let hosting = NSHostingController(rootView: swiftUIView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view, positioned: .above, relativeTo: dim)

        NSLayoutConstraint.activate([
            hosting.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hosting.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hosting.view.widthAnchor.constraint(equalToConstant: 640),
            hosting.view.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, constant: -80),
            hosting.view.heightAnchor.constraint(equalToConstant: 520),
        ])
        shortcutsOverlayHosting = hosting

        // ESC to dismiss (local monitor — the overlay is in our own app)
        shortcutsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.dismissShortcutsOverlay()
                return nil
            }
            return event
        }

        // Animate in
        dim.alphaValue = 0
        hosting.view.alphaValue = 0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            dim.animator().alphaValue = 1
            hosting.view.animator().alphaValue = 1
        }, completionHandler: nil)
    }

    @objc private func shortcutsDimClicked() {
        dismissShortcutsOverlay()
    }

    private func dismissShortcutsOverlay() {
        let hosting = shortcutsOverlayHosting
        let dim = shortcutsDimView
        shortcutsOverlayHosting = nil
        shortcutsDimView = nil

        if let monitor = shortcutsKeyMonitor {
            NSEvent.removeMonitor(monitor)
            shortcutsKeyMonitor = nil
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            hosting?.view.animator().alphaValue = 0
            dim?.animator().alphaValue = 0
        }, completionHandler: {
            hosting?.view.removeFromSuperview()
            dim?.removeFromSuperview()
        })
    }

    // MARK: - Divider Drag

    @objc private func handleLeftDividerDrag(_ gesture: NSPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let newWidth = max(Layout.sidebarMinWidth, min(Layout.sidebarMaxWidth, location.x))
        sidebarWidth = newWidth
        layoutSubviews()
    }

    @objc private func handleRightDividerDrag(_ gesture: NSPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let newWidth = max(Layout.sidebarMinWidth, min(Layout.sidebarMaxWidth, view.bounds.width - location.x))
        historyPanelWidth = newWidth
        layoutSubviews()
    }

    // MARK: - Theme re-render

    /// Walk all theme-sensitive subviews and force a redraw.
    /// Called by BrowserWindowController when ThemeStore.currentThemeID changes.
    func reapplyTheme() {
        // Force the entire view tree to redraw.
        view.needsDisplay = true
        view.layoutSubtreeIfNeeded()
        walkAndInvalidate(view)
    }

    private func walkAndInvalidate(_ v: NSView) {
        v.needsDisplay = true
        // Redraw layer-backed views
        if let layer = v.layer {
            layer.setNeedsDisplay()
            // Layer-backed views with a backgroundColor set from theme need re-setting
            v.needsLayout = true
        }
        for sub in v.subviews { walkAndInvalidate(sub) }
    }
}

// MARK: - Arc-Style Window Border Overlay

/// Draws a rounded-rect border inside the window frame on top of all content.
/// Passes all mouse events through (non-interactive).
final class WindowBorderOverlayView: NSView {

    private let borderLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(borderLayer)
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 3.5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let inset: CGFloat = 1.75
        let rect = bounds.insetBy(dx: inset, dy: inset)
        borderLayer.path = CGPath(roundedRect: rect, cornerWidth: 11, cornerHeight: 11, transform: nil)
        borderLayer.frame = bounds
    }

    // Pass all events through
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Hover Detector View

/// An invisible view that detects mouse enter/exit via a tracking area.
final class HoverDetectorView: NSView {

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    // Pass all clicks through — this view is purely for hover detection
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// MARK: - Resize Divider View

final class ResizeDividerView: NSView {

    private let lineLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        lineLayer.backgroundColor = Colors.borderLight.withAlphaComponent(0.4).cgColor
        layer?.addSublayer(lineLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let lineX = (bounds.width - 1) / 2
        lineLayer.frame = CGRect(x: lineX, y: 0, width: 1, height: bounds.height)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }
}
