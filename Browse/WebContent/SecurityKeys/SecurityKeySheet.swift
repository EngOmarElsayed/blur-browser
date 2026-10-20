import AppKit

/// The window-modal sheet shown while a page talks to a security key:
/// "Insert and touch your security key", the PIN prompt, account selection
/// and errors. Each `ask…` call suspends until the user answers; Cancel (or
/// `dismiss()`) answers with nil and calls `onCancel`.
@MainActor
final class SecurityKeySheet: NSObject {
    private enum Answer { case primary, cancel }

    var onCancel: (() -> Void)?

    private let panel: NSPanel
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let qrView = NSImageView()
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let pinField = NSSecureTextField()
    private let confirmField = NSSecureTextField()
    private let accountStack = NSStackView()
    private let spinner = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let primaryButton = NSButton(title: "Continue", target: nil, action: nil)
    private var accountButtons: [NSButton] = []

    private weak var parent: NSWindow?
    private var answer: CheckedContinuation<Answer, Never>?
    private var isPresented = false

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
                        styleMask: [.titled, .docModalWindow], backing: .buffered, defer: true)
        super.init()
        buildLayout()
    }

    private func buildLayout() {
        iconView.image = NSImage(systemSymbolName: "key.horizontal.fill", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: 28, weight: .regular)
        iconView.contentTintColor = .controlAccentColor

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        qrView.imageScaling = .scaleProportionallyUpOrDown
        qrView.translatesAutoresizingMaskIntoConstraints = false
        qrView.widthAnchor.constraint(equalToConstant: 180).isActive = true
        qrView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        qrView.wantsLayer = true
        qrView.layer?.backgroundColor = NSColor.white.cgColor
        qrView.layer?.cornerRadius = 6
        for label in [titleLabel, messageLabel, errorLabel, noteLabel] {
            label.preferredMaxLayoutWidth = 290
            label.isSelectable = false
        }

        pinField.placeholderString = "PIN"
        confirmField.placeholderString = "Confirm PIN"
        for field in [pinField, confirmField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 290).isActive = true
            field.target = self
            field.action = #selector(primaryPressed)
        }

        accountStack.orientation = .vertical
        accountStack.alignment = .leading
        accountStack.spacing = 6

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let text = NSStackView(views: [titleLabel, messageLabel, qrView, noteLabel, errorLabel, pinField, confirmField, accountStack])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 8

        let top = NSStackView(views: [iconView, text])
        top.alignment = .top
        top.spacing = 14

        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        primaryButton.target = self
        primaryButton.action = #selector(primaryPressed)
        primaryButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [spinner, NSView(), cancelButton, primaryButton])
        buttons.spacing = 8

        let root = NSStackView(views: [top, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 16, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: 380),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
        ])
        panel.contentView = content
    }

    // MARK: Presentation

    func present(on window: NSWindow) {
        guard !isPresented else { return }
        isPresented = true
        parent = window
        window.beginSheet(panel)
    }

    /// Closes the sheet; a pending `ask…` returns nil.
    func dismiss() {
        resolve(.cancel)
        guard isPresented else { return }
        isPresented = false
        parent?.endSheet(panel)
    }

    private func configure(title: String, message: String, error: String? = nil, spinning: Bool,
                           primary: String? = nil, cancel: String = "Cancel", symbol: String = "key.horizontal.fill") {
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        messageLabel.isHidden = message.isEmpty
        errorLabel.stringValue = error ?? ""
        errorLabel.isHidden = error == nil
        pinField.isHidden = true
        confirmField.isHidden = true
        accountStack.isHidden = true
        qrView.isHidden = true
        noteLabel.isHidden = true
        if spinning { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        primaryButton.title = primary ?? ""
        primaryButton.isHidden = primary == nil
        cancelButton.title = cancel
        // Return goes to Cancel when it is the only button (error screens).
        cancelButton.keyEquivalent = primary == nil ? "\r" : "\u{1b}"
        panel.layoutIfNeeded()
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
    }

    func showStatus(_ title: String, _ message: String) {
        configure(title: title, message: message, spinning: true)
    }

    /// The first screen: a QR code for a phone, while also waiting for a
    /// security key to be plugged in.
    func showChooser(_ title: String, _ message: String, qr: CGImage?) {
        configure(title: title, message: message, spinning: true, symbol: "qrcode")
        if let qr {
            qrView.image = NSImage(cgImage: qr, size: NSSize(width: 180, height: 180))
            qrView.isHidden = false
        }
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
    }

    /// A small line under the QR code, e.g. Bluetooth state; nil hides it.
    func setNote(_ note: String?) {
        noteLabel.stringValue = note ?? ""
        noteLabel.isHidden = note == nil || qrView.isHidden
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
    }

    // MARK: Questions

    private func waitForAnswer() async -> Answer {
        resolve(.cancel)
        return await withCheckedContinuation { answer = $0 }
    }

    private func resolve(_ value: Answer) {
        guard let answer else { return }
        self.answer = nil
        answer.resume(returning: value)
    }

    func confirm(_ title: String, _ message: String, button: String) async -> Bool {
        configure(title: title, message: message, spinning: false, primary: button)
        return await waitForAnswer() == .primary
    }

    /// Asks for an existing PIN, or a new one (twice) when `creating`.
    func askPIN(_ title: String, _ message: String, error: String?, creating: Bool) async -> String? {
        configure(title: title, message: message, error: error, spinning: false, primary: "Continue", symbol: "lock.fill")
        pinField.stringValue = ""
        confirmField.stringValue = ""
        pinField.placeholderString = creating ? "New PIN" : "PIN"
        pinField.isHidden = false
        confirmField.isHidden = !creating
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
        panel.makeFirstResponder(pinField)
        while true {
            guard await waitForAnswer() == .primary else { return nil }
            let pin = pinField.stringValue
            if creating, pin != confirmField.stringValue {
                errorLabel.stringValue = "The PINs don't match."
                errorLabel.isHidden = false
                panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
                continue
            }
            return pin
        }
    }

    func chooseAccount(_ title: String, _ message: String, accounts: [String]) async -> Int? {
        configure(title: title, message: message, spinning: false, primary: "Continue", symbol: "person.crop.circle")
        accountButtons.forEach { $0.removeFromSuperview() }
        accountButtons = accounts.enumerated().map { index, name in
            let button = NSButton(radioButtonWithTitle: name, target: self, action: #selector(accountPicked(_:)))
            button.tag = index
            button.state = index == 0 ? .on : .off
            return button
        }
        accountButtons.forEach { accountStack.addArrangedSubview($0) }
        accountStack.isHidden = false
        panel.setContentSize(panel.contentView?.fittingSize ?? panel.frame.size)
        guard await waitForAnswer() == .primary else { return nil }
        return accountButtons.first(where: { $0.state == .on })?.tag ?? 0
    }

    /// Shows a final message with one Close button and waits for it.
    func showFailure(_ title: String, _ message: String) async {
        configure(title: title, message: message, spinning: false, cancel: "Close", symbol: "exclamationmark.triangle.fill")
        _ = await waitForAnswer()
    }

    // MARK: Actions

    @objc private func accountPicked(_ sender: NSButton) {
        for button in accountButtons { button.state = button === sender ? .on : .off }
    }

    @objc private func primaryPressed() {
        guard !primaryButton.isHidden else { return }
        resolve(.primary)
    }

    @objc private func cancelPressed() {
        if answer != nil {
            resolve(.cancel)
        }
        onCancel?()
    }
}
