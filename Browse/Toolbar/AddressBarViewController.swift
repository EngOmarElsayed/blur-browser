import AppKit

@MainActor
final class AddressBarViewController: NSViewController, NSTextFieldDelegate {

    private let tabManager: TabManager
    private let sidebarToggleButton = NSButton()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let urlField = NSTextField()
    private let reloadButton = NSButton()
    private let readerButton = NSButton()
    private let shareButton = NSButton()
    private let moreButton = NSButton()
    private let progressBar = NSView()
    private var progressWidthConstraint: NSLayoutConstraint!
    private var pendingProgress: (Double, Bool)?

    // Constraints that swap depending on sidebar visibility
    private var sidebarToggleWidthConstraint: NSLayoutConstraint!
    private var backLeadingToToggle: NSLayoutConstraint!
    private var backLeadingToView: NSLayoutConstraint!
    private var toggleLeadingNormal: NSLayoutConstraint!   // 8pt when sidebar visible
    private var toggleLeadingCollapsed: NSLayoutConstraint! // 90pt when sidebar hidden

    /// Called when the sidebar toggle button is tapped
    var onToggleSidebar: (() -> Void)?

    /// Called when the more button is tapped (toggles address bar visibility)
    var onToggleAddressBar: (() -> Void)?

    /// Called when the reader-mode button is tapped
    var onToggleReaderMode: (() -> Void)?

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: Layout.toolbarHeight))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        setupViews()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let (progress, isLoading) = pendingProgress {
            pendingProgress = nil
            updateProgress(progress, isLoading: isLoading)
        }
    }

    private func setupViews() {
        // Sidebar toggle (always visible)
        configureNavButton(sidebarToggleButton, symbol: "sidebar.left", action: #selector(toggleSidebarTapped))

        // Back button
        configureNavButton(backButton, symbol: "chevron.left", action: #selector(goBack))
        // Forward button
        configureNavButton(forwardButton, symbol: "chevron.right", action: #selector(goForward))

        // URL field container — rounded pill
        let urlContainer = NSView()
        urlContainer.wantsLayer = true
        urlContainer.layer?.backgroundColor = Colors.surfacePrimary.cgColor
        urlContainer.layer?.borderColor = Colors.borderLight.withAlphaComponent(0.6).cgColor
        urlContainer.layer?.borderWidth = 1
        urlContainer.layer?.cornerRadius = Layout.urlBarHeight / 2

        // Lock icon
        let lockIcon = NSImageView()
        lockIcon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure")
        lockIcon.contentTintColor = Colors.foregroundMuted
        lockIcon.setContentHuggingPriority(.required, for: .horizontal)

        // URL text field
        urlField.isBordered = false
        urlField.drawsBackground = false
        urlField.font = .systemFont(ofSize: Typography.bodySize)
        urlField.textColor = Colors.foregroundSecondary
        urlField.placeholderString = "Search or enter URL..."
        urlField.focusRingType = .none
        urlField.delegate = self
        urlField.cell?.isScrollable = true
        urlField.cell?.lineBreakMode = .byTruncatingTail

        // Right-side buttons
        configureNavButton(reloadButton, symbol: "arrow.clockwise", action: #selector(reloadPage))
        configureNavButton(shareButton, symbol: "square.and.arrow.up", action: #selector(sharePage))
        configureNavButton(moreButton, symbol: "circle.circle", action: #selector(showMore))

        // Reader button — floating pill on the top-trailing edge, hidden by default
        configureReaderButton()

        // Layout with AutoLayout
        for v in [sidebarToggleButton, backButton, forwardButton, urlContainer, reloadButton, shareButton, moreButton, readerButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        for v in [lockIcon, urlField, readerButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            urlContainer.addSubview(v)
        }

        // Use high (but not required) priority for horizontal chain constraints so
        // they don't conflict with the autoresizing-mask constraint when the
        // toolbar's parent view starts at width 0 during the initial layout pass.
        let highPriority = NSLayoutConstraint.Priority(999)

        // Swappable constraints for sidebar toggle visibility
        sidebarToggleWidthConstraint = sidebarToggleButton.widthAnchor.constraint(equalToConstant: 0)
        backLeadingToToggle = backButton.leadingAnchor.constraint(equalTo: sidebarToggleButton.trailingAnchor, constant: 8)
        backLeadingToToggle.priority = highPriority

        let backLeading = backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)
        backLeading.priority = highPriority
        backLeadingToView = backLeading

        // Sidebar toggle always visible — always use 28pt width
        sidebarToggleWidthConstraint.constant = 28
        sidebarToggleWidthConstraint.isActive = true
        backLeadingToToggle.isActive = true

        let urlLeading = urlContainer.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 12)
        urlLeading.priority = highPriority
        let urlTrailing = urlContainer.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -12)
        urlTrailing.priority = highPriority

        let moreTrailing = moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8)
        moreTrailing.priority = highPriority

        // Helper to create a constraint at high (non-required) priority
        func highPri(_ c: NSLayoutConstraint) -> NSLayoutConstraint {
            c.priority = highPriority
            return c
        }

        toggleLeadingNormal = sidebarToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)
        toggleLeadingNormal.priority = highPriority
        toggleLeadingCollapsed = sidebarToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 90)
        toggleLeadingCollapsed.priority = highPriority
        toggleLeadingNormal.isActive = true

        NSLayoutConstraint.activate([
            sidebarToggleButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sidebarToggleButton.heightAnchor.constraint(equalToConstant: 28),

            backButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            highPri(backButton.widthAnchor.constraint(equalToConstant: 28)),
            backButton.heightAnchor.constraint(equalToConstant: 28),

            highPri(forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4)),
            forwardButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            highPri(forwardButton.widthAnchor.constraint(equalToConstant: 28)),
            forwardButton.heightAnchor.constraint(equalToConstant: 28),

            urlLeading,
            urlTrailing,
            urlContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            urlContainer.heightAnchor.constraint(equalToConstant: Layout.urlBarHeight),

            highPri(lockIcon.leadingAnchor.constraint(equalTo: urlContainer.leadingAnchor, constant: 14)),
            lockIcon.centerYAnchor.constraint(equalTo: urlContainer.centerYAnchor),
            highPri(lockIcon.widthAnchor.constraint(equalToConstant: 14)),
            lockIcon.heightAnchor.constraint(equalToConstant: 14),

            highPri(urlField.leadingAnchor.constraint(equalTo: lockIcon.trailingAnchor, constant: 6)),
            highPri(urlField.trailingAnchor.constraint(equalTo: urlContainer.trailingAnchor, constant: -14)),
            urlField.centerYAnchor.constraint(equalTo: urlContainer.centerYAnchor),

            moreTrailing,
            moreButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            highPri(moreButton.widthAnchor.constraint(equalToConstant: 28)),
            moreButton.heightAnchor.constraint(equalToConstant: 28),

            highPri(shareButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -12)),
            shareButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            highPri(shareButton.widthAnchor.constraint(equalToConstant: 28)),
            shareButton.heightAnchor.constraint(equalToConstant: 28),

            // Reader button — floating pill pinned to top-trailing corner
            // Reader pill sits on top of the URL bar, aligned to its trailing edge.
            // Anchored to the toolbar's top so it stays inside the toolbar's bounds.
            highPri(readerButton.trailingAnchor.constraint(equalTo: urlContainer.trailingAnchor, constant: -10)),
            readerButton.centerYAnchor.constraint(equalTo: urlContainer.centerYAnchor),
            highPri(readerButton.widthAnchor.constraint(equalToConstant: 14)),
            readerButton.heightAnchor.constraint(equalToConstant: 14),

            highPri(reloadButton.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -12)),
            reloadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            highPri(reloadButton.widthAnchor.constraint(equalToConstant: 28)),
            reloadButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Progress bar — thin line at the very bottom of the toolbar
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = Colors.accentPrimary.cgColor
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        view.addSubview(progressBar)

        progressWidthConstraint = progressBar.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            progressBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            progressBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
            progressWidthConstraint,
        ])
    }

    private func configureNavButton(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.contentTintColor = Colors.foregroundMuted
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureReaderButton() {
        readerButton.image = NSImage(
            systemSymbolName: "doc.plaintext",
            accessibilityDescription: "Reader Mode"
        )
        readerButton.imageScaling = .scaleProportionallyDown
        readerButton.imagePosition = .imageOnly
        readerButton.isBordered = false
        readerButton.bezelStyle = .accessoryBarAction
        readerButton.contentTintColor = Colors.foregroundSecondary
        readerButton.target = self
        readerButton.action = #selector(toggleReaderMode)
        readerButton.wantsLayer = true
        readerButton.layer?.shadowColor = NSColor.black.withAlphaComponent(0.12).cgColor
        readerButton.layer?.shadowOffset = CGSize(width: 0, height: -1)
        readerButton.layer?.shadowRadius = 3
        readerButton.layer?.shadowOpacity = 1
        readerButton.isHidden = true
    }

    /// Show or hide the reader-mode pill button based on whether the current page
    /// has content that can be parsed as an article.
    func setReaderAvailable(_ available: Bool) {
        readerButton.isHidden = !available
    }

    func focusAndSelectAll() {
        view.window?.makeFirstResponder(urlField)
        urlField.currentEditor()?.selectAll(nil)
    }

    func updateForTab(_ tab: BrowserTab?) {
        guard let tab else {
            urlField.stringValue = ""
            backButton.isEnabled = false
            forwardButton.isEnabled = false
            updateProgress(0, isLoading: false)
            return
        }
        // Don't overwrite while the user is actively editing the URL field
        if view.window?.firstResponder != urlField.currentEditor() {
            urlField.stringValue = tab.displayURL
        }
        backButton.isEnabled = tab.canGoBack
        forwardButton.isEnabled = tab.canGoForward
        updateProgress(tab.estimatedProgress, isLoading: tab.isLoading)
    }

    func updateProgress(_ progress: Double, isLoading: Bool) {
        let barPadding: CGFloat = 16   // 8 leading + 8 trailing
        let maxBarWidth = view.bounds.width - barPadding
        guard maxBarWidth > 0 else {
            pendingProgress = (progress, isLoading)
            return
        }

        if !isLoading || progress >= 1.0 {
            if !progressBar.isHidden {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.2
                    progressWidthConstraint.animator().constant = maxBarWidth
                }, completionHandler: { [weak self] in
                    self?.progressBar.isHidden = true
                    self?.progressWidthConstraint.constant = 0
                })
            }
            return
        }

        progressBar.isHidden = false
        let targetWidth = maxBarWidth * CGFloat(progress)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            progressWidthConstraint.animator().constant = targetWidth
        }
    }

    // MARK: - Actions

    @objc private func goBack() {
        tabManager.selectedTab?.webView.goBack()
    }

    @objc private func goForward() {
        tabManager.selectedTab?.webView.goForward()
    }

    @objc private func reloadPage() {
        tabManager.selectedTab?.webView.reload()
    }

    @objc private func toggleSidebarTapped() {
        onToggleSidebar?()
    }

    @objc private func sharePage() {
        guard let url = tabManager.selectedTab?.url else { return }
        let items: [Any] = [url]
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: shareButton.bounds, of: shareButton, preferredEdge: .minY)
    }

    @objc private func showMore() {
        onToggleAddressBar?()
    }

    @objc private func toggleReaderMode() {
        onToggleReaderMode?()
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        if collapsed {
            toggleLeadingNormal.isActive = false
            toggleLeadingCollapsed.isActive = true
        } else {
            toggleLeadingCollapsed.isActive = false
            toggleLeadingNormal.isActive = true
        }
        view.layoutSubtreeIfNeeded()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ obj: Notification) {
        // When the user clicks away without pressing Enter, restore the current URL
        urlField.stringValue = tabManager.selectedTab?.displayURL ?? ""
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let text = urlField.stringValue.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                tabManager.navigate(to: text)
            }
            view.window?.makeFirstResponder(nil)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            urlField.stringValue = tabManager.selectedTab?.displayURL ?? ""
            view.window?.makeFirstResponder(nil)
            return true
        }
        return false
    }
}
