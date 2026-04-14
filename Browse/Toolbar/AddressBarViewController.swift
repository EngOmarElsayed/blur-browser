import AppKit

@MainActor
final class AddressBarViewController: NSViewController, NSTextFieldDelegate {

    private let tabManager: TabManager
    private let sidebarToggleButton = NSButton()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let urlField = NSTextField()
    private let reloadButton = NSButton()
    private let shareButton = NSButton()
    private let moreButton = NSButton()

    // Constraints that swap depending on sidebar visibility
    private var sidebarToggleWidthConstraint: NSLayoutConstraint!
    private var backLeadingToToggle: NSLayoutConstraint!
    private var backLeadingToView: NSLayoutConstraint!

    /// Called when the sidebar toggle button is tapped
    var onToggleSidebar: (() -> Void)?

    init(tabManager: TabManager) {
        self.tabManager = tabManager
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: Layout.toolbarHeight))
        view.wantsLayer = true
        setupViews()
    }

    private func setupViews() {
        // Sidebar toggle (shown when sidebar is collapsed)
        configureNavButton(sidebarToggleButton, symbol: "sidebar.right", action: #selector(toggleSidebarTapped))
        sidebarToggleButton.isHidden = true

        // Back button
        configureNavButton(backButton, symbol: "chevron.left", action: #selector(goBack))
        // Forward button
        configureNavButton(forwardButton, symbol: "chevron.right", action: #selector(goForward))

        // URL field container — rounded pill
        let urlContainer = NSView()
        urlContainer.wantsLayer = true
        urlContainer.layer?.backgroundColor = Colors.surfacePrimary.cgColor
        urlContainer.layer?.borderColor = Colors.borderLight.cgColor
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
        configureNavButton(moreButton, symbol: "ellipsis", action: #selector(showMore))

        // Layout with AutoLayout
        for v in [sidebarToggleButton, backButton, forwardButton, urlContainer, reloadButton, shareButton, moreButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        for v in [lockIcon, urlField] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            urlContainer.addSubview(v)
        }

        // Swappable constraints for sidebar toggle visibility
        sidebarToggleWidthConstraint = sidebarToggleButton.widthAnchor.constraint(equalToConstant: 0)
        backLeadingToToggle = backButton.leadingAnchor.constraint(equalTo: sidebarToggleButton.trailingAnchor, constant: 8)
        backLeadingToView = backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8)

        // Start with sidebar visible (toggle hidden)
        sidebarToggleWidthConstraint.isActive = true
        backLeadingToView.isActive = true

        NSLayoutConstraint.activate([
            sidebarToggleButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 90),
            sidebarToggleButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            sidebarToggleButton.heightAnchor.constraint(equalToConstant: 28),

            backButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 28),
            backButton.heightAnchor.constraint(equalToConstant: 28),

            forwardButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 4),
            forwardButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            forwardButton.widthAnchor.constraint(equalToConstant: 28),
            forwardButton.heightAnchor.constraint(equalToConstant: 28),

            urlContainer.leadingAnchor.constraint(equalTo: forwardButton.trailingAnchor, constant: 12),
            urlContainer.trailingAnchor.constraint(equalTo: reloadButton.leadingAnchor, constant: -12),
            urlContainer.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            urlContainer.heightAnchor.constraint(equalToConstant: Layout.urlBarHeight),

            lockIcon.leadingAnchor.constraint(equalTo: urlContainer.leadingAnchor, constant: 14),
            lockIcon.centerYAnchor.constraint(equalTo: urlContainer.centerYAnchor),
            lockIcon.widthAnchor.constraint(equalToConstant: 14),
            lockIcon.heightAnchor.constraint(equalToConstant: 14),

            urlField.leadingAnchor.constraint(equalTo: lockIcon.trailingAnchor, constant: 6),
            urlField.trailingAnchor.constraint(equalTo: urlContainer.trailingAnchor, constant: -14),
            urlField.centerYAnchor.constraint(equalTo: urlContainer.centerYAnchor),

            moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            moreButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 28),
            moreButton.heightAnchor.constraint(equalToConstant: 28),

            shareButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -4),
            shareButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            shareButton.widthAnchor.constraint(equalToConstant: 28),
            shareButton.heightAnchor.constraint(equalToConstant: 28),

            reloadButton.trailingAnchor.constraint(equalTo: shareButton.leadingAnchor, constant: -4),
            reloadButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 28),
            reloadButton.heightAnchor.constraint(equalToConstant: 28),
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

    func focusAndSelectAll() {
        view.window?.makeFirstResponder(urlField)
        urlField.currentEditor()?.selectAll(nil)
    }

    func updateForTab(_ tab: BrowserTab?) {
        guard let tab else {
            urlField.stringValue = ""
            backButton.isEnabled = false
            forwardButton.isEnabled = false
            return
        }
        // Don't overwrite while the user is actively editing the URL field
        if view.window?.firstResponder != urlField.currentEditor() {
            urlField.stringValue = tab.displayURL
        }
        backButton.isEnabled = tab.canGoBack
        forwardButton.isEnabled = tab.canGoForward
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
        // Placeholder for more menu
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        sidebarToggleButton.isHidden = !collapsed
        if collapsed {
            sidebarToggleWidthConstraint.constant = 28
            backLeadingToView.isActive = false
            backLeadingToToggle.isActive = true
        } else {
            sidebarToggleWidthConstraint.constant = 0
            backLeadingToToggle.isActive = false
            backLeadingToView.isActive = true
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
