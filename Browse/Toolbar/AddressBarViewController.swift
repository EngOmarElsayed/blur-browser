import AppKit
import WebKit

@MainActor
final class AddressBarViewController: NSViewController, NSTextFieldDelegate {

    private let tabManager: TabManager
    private let sidebarToggleButton = NSButton()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let urlField = FocusAwareTextField()
    private let urlContainer = NSView()
    private let urlGlass = NSGlassEffectView()
    /// Horizontal inset of the progress hairline inside the URL capsule, so it
    /// stays clear of the rounded ends.
    private let progressInset: CGFloat = Layout.toolbarControlHeight / 2
    private let lockIcon = NSImageView()
    private let reloadButton = NSButton()
    private let readerButton = NSButton()
    private let shareButton = NSButton()
    private let moreButton = NSButton()
    private let agentButton = NSButton()
    /// Red capsule shown while the agent is in Dangerous mode for this window.
    private let dangerBadge = NSGlassEffectView()
    private let progressBar = NSView()
    /// Web extension toolbar buttons get their own glass capsule, left of
    /// [reload · share · focus]; hidden when no extension has an action.
    private let extensionsStack = NSStackView()
    private let extensionsGlass = NSGlassEffectView()
    private var extensionButtons: [String: NSButton] = [:]
    private var progressWidthConstraint: NSLayoutConstraint!
    private var pendingProgress: (Double, Bool)?

    // Constraints that swap depending on sidebar visibility
    private var toggleLeadingNormal: NSLayoutConstraint!    // sidebar visible
    private var toggleLeadingCollapsed: NSLayoutConstraint! // sidebar hidden — clear the traffic lights

    /// Called when the sidebar toggle button is tapped
    var onToggleSidebar: (() -> Void)?

    /// Called when the more button is tapped (toggles address bar visibility)
    var onToggleAddressBar: (() -> Void)?

    /// Called when the reader-mode button is tapped
    var onToggleReaderMode: (() -> Void)?

    /// Called when the agent button or the Dangerous-mode badge is tapped
    var onToggleAgent: (() -> Void)?

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
        configureNavButton(sidebarToggleButton, symbol: "sidebar.left", tip: "Toggle Sidebar", action: #selector(toggleSidebarTapped))
        configureNavButton(backButton, symbol: "chevron.backward", tip: "Back", action: #selector(goBack))
        configureNavButton(forwardButton, symbol: "chevron.forward", tip: "Forward", action: #selector(goForward))
        configureNavButton(reloadButton, symbol: "arrow.clockwise", tip: "Reload", action: #selector(reloadPage))
        configureNavButton(shareButton, symbol: "square.and.arrow.up", tip: "Share", action: #selector(sharePage))
        configureNavButton(moreButton, symbol: "arrow.up.left.and.arrow.down.right", tip: "Focus Mode", action: #selector(showMore))
        configureNavButton(agentButton, symbol: "sparkles", tip: "Agent (⌥⌘A)", action: #selector(toggleAgentTapped))
        configureDangerBadge()

        // Clicking the URL pill opens Quick Search (the field itself is read-only)
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleUrlContainerMousClick))
        urlContainer.addGestureRecognizer(clickGesture)

        // Lock icon
        lockIcon.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure")
        lockIcon.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        lockIcon.contentTintColor = Colors.foregroundSecondary
        lockIcon.setContentHuggingPriority(.required, for: .horizontal)

        // URL text field — sits on glass, so it uses the theme foreground
        urlField.isBordered = false
        urlField.isEditable = false
        urlField.isSelectable = true
        urlField.drawsBackground = false
        urlField.font = .systemFont(ofSize: Typography.bodySize, weight: .regular)
        urlField.textColor = Colors.foregroundPrimary
        urlField.placeholderString = "Search or enter website"
        urlField.focusRingType = .none
        urlField.delegate = self
        urlField.onFocus = { [weak self] in self?.isEditingURL = true }
        urlField.cell?.isScrollable = true
        urlField.cell?.lineBreakMode = .byTruncatingTail

        configureReaderButton()

        // URL capsule content
        urlContainer.wantsLayer = true
        for v in [lockIcon, urlField, readerButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            urlContainer.addSubview(v)
        }
        urlGlass.contentView = urlContainer
        urlGlass.cornerRadius = Layout.toolbarControlHeight / 2

        // Liquid Glass capsules: [sidebar · back · forward]  [ url ]  [reload · share · focus]
        let leftGroup = makeGlassGroup([sidebarToggleButton, backButton, forwardButton])
        let rightGroup = makeGlassGroup([reloadButton, shareButton, agentButton, moreButton])

        extensionsStack.orientation = .horizontal
        extensionsStack.spacing = 0
        extensionsStack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        extensionsGlass.contentView = extensionsStack
        extensionsGlass.cornerRadius = Layout.toolbarControlHeight / 2
        extensionsGlass.isHidden = true

        // Extensions capsule, danger badge and page actions. Hidden views are
        // detached, so the URL bar grows into their space.
        let trailingGroups = NSStackView(views: [extensionsGlass, dangerBadge, rightGroup])
        trailingGroups.orientation = .horizontal
        trailingGroups.spacing = 8
        trailingGroups.detachesHiddenViews = true

        for v in [leftGroup, urlGlass, trailingGroups] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }

        // Use high (but not required) priority for horizontal chain constraints so
        // they don't conflict with the autoresizing-mask constraint when the
        // toolbar's parent view starts at width 0 during the initial layout pass.
        let highPriority = NSLayoutConstraint.Priority(999)
        func highPri(_ c: NSLayoutConstraint) -> NSLayoutConstraint {
            c.priority = highPriority
            return c
        }

        // Leading inset swaps when the sidebar collapses so the group clears the traffic lights
        toggleLeadingNormal = highPri(leftGroup.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4))
        toggleLeadingCollapsed = highPri(leftGroup.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 84))
        toggleLeadingNormal.isActive = true

        let controlHeight = Layout.toolbarControlHeight
        NSLayoutConstraint.activate([
            leftGroup.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            leftGroup.heightAnchor.constraint(equalToConstant: controlHeight),

            highPri(urlGlass.leadingAnchor.constraint(equalTo: leftGroup.trailingAnchor, constant: 10)),
            highPri(urlGlass.trailingAnchor.constraint(equalTo: trailingGroups.leadingAnchor, constant: -10)),
            urlGlass.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            urlGlass.heightAnchor.constraint(equalToConstant: controlHeight),

            highPri(trailingGroups.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4)),
            trailingGroups.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            rightGroup.heightAnchor.constraint(equalToConstant: controlHeight),
            extensionsGlass.heightAnchor.constraint(equalToConstant: controlHeight),
            dangerBadge.heightAnchor.constraint(equalToConstant: controlHeight),

            highPri(lockIcon.leadingAnchor.constraint(equalTo: urlContainer.leadingAnchor, constant: 14)),
            lockIcon.centerYAnchor.constraint(equalTo: urlContainer.centerYAnchor),
            highPri(lockIcon.widthAnchor.constraint(equalToConstant: 12)),

            highPri(urlField.leadingAnchor.constraint(equalTo: lockIcon.trailingAnchor, constant: 8)),
            highPri(urlField.trailingAnchor.constraint(equalTo: readerButton.leadingAnchor, constant: -8)),
            urlField.centerYAnchor.constraint(equalTo: urlContainer.centerYAnchor),

            highPri(readerButton.trailingAnchor.constraint(equalTo: urlContainer.trailingAnchor, constant: -10)),
            readerButton.centerYAnchor.constraint(equalTo: urlContainer.centerYAnchor),
            highPri(readerButton.widthAnchor.constraint(equalToConstant: 22)),
            readerButton.heightAnchor.constraint(equalToConstant: 22),
        ])

        // Progress — a hairline along the bottom of the URL capsule
        progressBar.wantsLayer = true
        progressBar.layer?.backgroundColor = Colors.accentPrimary.cgColor
        progressBar.layer?.cornerRadius = 1
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.isHidden = true
        urlContainer.addSubview(progressBar)

        progressWidthConstraint = progressBar.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            progressBar.leadingAnchor.constraint(equalTo: urlContainer.leadingAnchor, constant: progressInset),
            progressBar.bottomAnchor.constraint(equalTo: urlContainer.bottomAnchor, constant: -1),
            progressBar.heightAnchor.constraint(equalToConstant: 2),
            progressWidthConstraint,
        ])
    }

    /// A capsule of Liquid Glass holding a row of borderless icon buttons.
    private func makeGlassGroup(_ buttons: [NSButton]) -> NSGlassEffectView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        for button in buttons {
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 30),
                button.heightAnchor.constraint(equalToConstant: 28),
            ])
        }
        let glass = NSGlassEffectView()
        glass.contentView = stack
        glass.cornerRadius = Layout.toolbarControlHeight / 2
        return glass
    }

    private func configureNavButton(_ button: NSButton, symbol: String, tip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        button.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.contentTintColor = Colors.foregroundSecondary
        button.toolTip = tip
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func configureDangerBadge() {
        let button = NSButton(title: "Dangerous", image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)!, target: self, action: #selector(toggleAgentTapped))
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.symbolConfiguration = .init(pointSize: 11, weight: .bold)
        button.font = .systemFont(ofSize: Typography.smallSize, weight: .semibold)
        button.contentTintColor = Colors.foregroundInverse
        button.attributedTitle = NSAttributedString(string: "Dangerous", attributes: [
            .foregroundColor: Colors.foregroundInverse,
            .font: NSFont.systemFont(ofSize: Typography.smallSize, weight: .semibold),
        ])
        button.toolTip = "Agent is in Dangerous mode for this window — it acts without asking. Click to open the Agent panel."
        button.setAccessibilityLabel("Agent Dangerous mode is on")

        let content = NSView()
        button.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        dangerBadge.contentView = content
        dangerBadge.cornerRadius = Layout.toolbarControlHeight / 2
        dangerBadge.tintColor = Colors.danger
        dangerBadge.isHidden = true
    }

    /// Show the toolbar's Dangerous-mode indicator for this window's agent session.
    func setAgentDangerous(_ dangerous: Bool) {
        dangerBadge.isHidden = !dangerous
        agentButton.contentTintColor = dangerous ? Colors.danger : Colors.foregroundSecondary
    }

    private func configureReaderButton() {
        readerButton.image = NSImage(
            systemSymbolName: "doc.plaintext",
            accessibilityDescription: "Reader Mode"
        )
        readerButton.symbolConfiguration = .init(pointSize: 12, weight: .medium)
        readerButton.toolTip = "Reader Mode"
        readerButton.imagePosition = .imageOnly
        readerButton.isBordered = false
        readerButton.bezelStyle = .accessoryBarAction
        readerButton.contentTintColor = Colors.accentPrimary
        readerButton.target = self
        readerButton.action = #selector(toggleReaderMode)
        readerButton.isHidden = true
    }

    /// Show or hide the reader-mode pill button based on whether the current page
    /// has content that can be parsed as an article.
    func setReaderAvailable(_ available: Bool) {
        readerButton.isHidden = !available
    }

    /// Update the reader pill's appearance to reflect whether reader mode is
    /// currently active on the selected tab.
    func setReaderActive(_ active: Bool) {
        readerButton.image = NSImage(
            systemSymbolName: active ? "doc.plaintext.fill" : "doc.plaintext",
            accessibilityDescription: "Reader Mode"
        )
        readerButton.contentTintColor = Colors.accentPrimary
    }

    /// Re-apply theme-dependent layer colors and control tints after a theme switch.
    /// Views that cache theme tokens in stored properties (layer colors, contentTintColor,
    /// textColor) don't re-read on invalidate, so we rewrite them here.
    func applyActiveTheme() {
        progressBar.layer?.backgroundColor = Colors.accentPrimary.cgColor

        // Nav button tints
        for button in [sidebarToggleButton, backButton, forwardButton, reloadButton, shareButton, moreButton] {
            button.contentTintColor = Colors.foregroundSecondary
        }
        reloadExtensionButtons()
        setAgentDangerous(!dangerBadge.isHidden)

        urlField.textColor = Colors.foregroundPrimary
        lockIcon.contentTintColor = Colors.foregroundSecondary
        updateURLGlassTint()

        // Reader button defaults to the inactive tint; callers will flip it active
        // again via setReaderActive(_:) on the next tab update if needed.
        readerButton.contentTintColor = Colors.accentPrimary

        // Re-render any theme-aware text/icon tints by forcing an update path
        view.needsDisplay = true
    }

    func focusAndSelectAll() {
        urlField.selectText(urlField)
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
        let maxBarWidth = urlContainer.bounds.width - progressInset * 2
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

    // MARK: - Web extension buttons

    /// Rebuild one button per installed extension that has a toolbar action,
    /// reflecting the action's state for the selected tab.
    func reloadExtensionButtons() {
        let manager = WebExtensionManager.shared
        guard let windowController = view.window?.windowController as? BrowserWindowController else {
            extensionsGlass.isHidden = manager.installed.isEmpty
            return
        }
        var seen = Set<String>()
        for item in manager.installed {
            guard let action = manager.action(for: item.context, in: windowController) else { continue }
            seen.insert(item.id)
            let button = extensionButtons[item.id] ?? makeExtensionButton(id: item.id)
            let icon = action.icon(for: CGSize(width: 16, height: 16))
                ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
            icon?.size = NSSize(width: 16, height: 16)
            button.image = icon
            button.contentTintColor = action.icon(for: CGSize(width: 16, height: 16)) == nil ? Colors.foregroundSecondary : nil
            button.toolTip = action.label.isEmpty ? item.displayName : action.label
            button.isEnabled = action.isEnabled
            setBadge(action.badgeText, on: button)
        }
        for (id, button) in extensionButtons where !seen.contains(id) {
            extensionsStack.removeArrangedSubview(button)
            button.removeFromSuperview()
            extensionButtons[id] = nil
        }
        extensionsGlass.isHidden = extensionButtons.isEmpty
    }

    private func makeExtensionButton(id: String) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .accessoryBarAction
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.target = self
        button.action = #selector(extensionButtonTapped(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        extensionsStack.addArrangedSubview(button)
        extensionButtons[id] = button
        return button
    }

    private func setBadge(_ text: String, on button: NSButton) {
        let badgeID = NSUserInterfaceItemIdentifier("badge")
        let existing = button.subviews.first { $0.identifier == badgeID } as? NSTextField
        guard !text.isEmpty else {
            existing?.removeFromSuperview()
            return
        }
        let badge = existing ?? {
            let label = NSTextField(labelWithString: "")
            label.identifier = badgeID
            label.font = .systemFont(ofSize: 8, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.wantsLayer = true
            label.layer?.backgroundColor = Colors.accentPrimary.cgColor
            label.layer?.cornerRadius = 5
            label.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
                label.topAnchor.constraint(equalTo: button.topAnchor, constant: 1),
                label.heightAnchor.constraint(equalToConstant: 10),
                label.widthAnchor.constraint(greaterThanOrEqualToConstant: 10),
            ])
            return label
        }()
        badge.stringValue = String(text.prefix(4))
    }

    @objc private func extensionButtonTapped(_ sender: NSButton) {
        let manager = WebExtensionManager.shared
        guard let id = sender.identifier?.rawValue,
              let item = manager.installed.first(where: { $0.id == id }),
              let windowController = view.window?.windowController as? BrowserWindowController else { return }
        // Anchor the popup (if any) under the clicked button.
        manager.popupAnchor = { [weak sender] _ in sender }
        manager.performAction(for: item.context, in: windowController)
    }

    // MARK: - Actions
    @objc func handleUrlContainerMousClick(_ gesture: NSClickGestureRecognizer) {
        guard let wc = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
        wc.openQuickSearch()
    }

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

    @objc private func toggleAgentTapped() {
        onToggleAgent?()
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

    /// While editing, the URL capsule picks up a faint accent tint — a softer
    /// focus cue than a ring on glass.
    private var isEditingURL = false {
        didSet { updateURLGlassTint() }
    }

    private func updateURLGlassTint() {
        urlGlass.tintColor = isEditingURL ? Colors.accentPrimary.withAlphaComponent(0.18) : nil
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        isEditingURL = false
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

// MARK: - Focus-aware text field

/// Reports when it becomes first responder — `controlTextDidBeginEditing` only
/// fires on the first keystroke, too late for a focus cue.
private final class FocusAwareTextField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { onFocus?() }
        return didBecome
    }
}
