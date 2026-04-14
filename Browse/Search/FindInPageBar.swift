import AppKit

@MainActor
final class FindInPageBar: NSView {

    private let controller: FindInPageController
    private let searchField = NSTextField()
    private let matchLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()
    var onDismiss: (() -> Void)?

    private var debounceTask: Task<Void, Never>?

    init(controller: FindInPageController) {
        self.controller = controller
        super.init(frame: .zero)
        setup()

        controller.onMatchUpdate = { [weak self] current, total in
            Task { @MainActor in
                if total == 0 {
                    self?.matchLabel.stringValue = ""
                } else {
                    self?.matchLabel.stringValue = "\(current) of \(total)"
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Colors.surfacePrimary.cgColor
        layer?.borderColor = Colors.borderLight.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 12

        // Drop shadow
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.06).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 8
        layer?.shadowOpacity = 1

        // Search icon
        let searchIcon = NSImageView()
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
        searchIcon.contentTintColor = Colors.foregroundMuted

        // Search field
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.font = .systemFont(ofSize: Typography.bodySize)
        searchField.textColor = Colors.foregroundPrimary
        searchField.placeholderString = "Find in page..."
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.cell?.isScrollable = true

        // Match label
        matchLabel.font = .systemFont(ofSize: Typography.smallSize)
        matchLabel.textColor = Colors.foregroundMuted

        // Nav buttons
        configureButton(prevButton, symbol: "chevron.up", action: #selector(findPrevious))
        configureButton(nextButton, symbol: "chevron.down", action: #selector(findNext))
        configureButton(closeButton, symbol: "xmark", action: #selector(dismiss))

        // Layout
        for v in [searchIcon, searchField, matchLabel, prevButton, nextButton, closeButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 16),
            searchIcon.heightAnchor.constraint(equalToConstant: 16),

            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),

            matchLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            matchLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            prevButton.leadingAnchor.constraint(equalTo: matchLabel.trailingAnchor, constant: 8),
            prevButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            prevButton.widthAnchor.constraint(equalToConstant: 20),
            prevButton.heightAnchor.constraint(equalToConstant: 20),

            nextButton.leadingAnchor.constraint(equalTo: prevButton.trailingAnchor, constant: 4),
            nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 20),
            nextButton.heightAnchor.constraint(equalToConstant: 20),

            closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),
        ])

        matchLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        matchLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureButton(_ button: NSButton, symbol: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.isBordered = false
        button.contentTintColor = Colors.foregroundMuted
        button.target = self
        button.action = action
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    @objc private func findPrevious() { controller.findPrevious() }
    @objc private func findNext() { controller.findNext() }
    @objc private func dismiss() { onDismiss?() }
}

extension FindInPageBar: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        debounceTask?.cancel()
        let text = searchField.stringValue
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            controller.search(for: text)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            controller.findNext()
            return true
        }
        return false
    }
}
