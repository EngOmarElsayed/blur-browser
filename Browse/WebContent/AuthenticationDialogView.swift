import AppKit

/// A centered alert-style panel that appears over the web content
/// when a website requires HTTP authentication (Basic/Digest).
@MainActor
final class AuthenticationDialogView: NSView {

    static let panelWidth: CGFloat = 380
    static let panelHeight: CGFloat = 260

    var onSubmit: ((String, String) -> Void)?
    var onCancel: (() -> Void)?

    private let usernameField = NSTextField()
    private let passwordField = NSSecureTextField()

    init(host: String, realm: String?) {
        super.init(frame: .zero)
        setup(host: host, realm: realm)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup(host: String, realm: String?) {
        wantsLayer = true
        layer?.backgroundColor = Colors.chromeBg.cgColor
        layer?.cornerRadius = 14
        layer?.borderColor = Colors.borderLight.cgColor
        layer?.borderWidth = 1

        // Shadow
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowRadius = 20
        layer?.shadowOpacity = 1

        // Icon
        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: "Authentication")
        iconView.contentTintColor = Colors.foregroundPrimary
        iconView.imageScaling = .scaleProportionallyUpOrDown

        // Title
        let message: String
        if let realm, !realm.isEmpty {
            message = "\"\(host)\" requires a login.\n\(realm)"
        } else {
            message = "\"\(host)\" requires a login."
        }
        let titleLabel = NSTextField(labelWithString: message)
        titleLabel.font = NSFont(name: Typography.fontFamily, size: 13) ?? .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Colors.foregroundPrimary
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 3
        titleLabel.alignment = .center

        // Username field in rounded wrapper
        configureTextField(usernameField, placeholder: "Username")
        usernameField.contentType = .username
        let usernameWrapper = makeFieldWrapper(for: usernameField)

        // Password field in rounded wrapper
        configureTextField(passwordField, placeholder: "Password")
        passwordField.contentType = .password
        let passwordWrapper = makeFieldWrapper(for: passwordField)

        // Buttons
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}" // Escape

        let loginButton = NSButton(title: "Log In", target: self, action: #selector(submitTapped))
        loginButton.bezelStyle = .rounded
        loginButton.controlSize = .large
        loginButton.keyEquivalent = "\r" // Enter

        // Button row
        let buttonStack = NSStackView(views: [cancelButton, loginButton])
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8

        // Layout
        for v in [iconView, titleLabel, usernameWrapper, passwordWrapper, buttonStack] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            // Icon
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            // Title
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            // Username wrapper
            usernameWrapper.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            usernameWrapper.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            usernameWrapper.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            usernameWrapper.heightAnchor.constraint(equalToConstant: 32),

            // Password wrapper
            passwordWrapper.topAnchor.constraint(equalTo: usernameWrapper.bottomAnchor, constant: 8),
            passwordWrapper.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            passwordWrapper.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            passwordWrapper.heightAnchor.constraint(equalToConstant: 32),

            // Buttons
            buttonStack.topAnchor.constraint(equalTo: passwordWrapper.bottomAnchor, constant: 16),
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            buttonStack.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Focus username field on appear
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.usernameField)
        }
    }

    private func configureTextField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = NSFont(name: Typography.fontFamily, size: 13) ?? .systemFont(ofSize: 13)
        field.textColor = Colors.foregroundPrimary
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.focusRingType = .none
    }

    /// Wraps a text field in a rounded container with horizontal padding.
    private func makeFieldWrapper(for field: NSTextField) -> NSView {
        let wrapper = NSView()
        wrapper.wantsLayer = true
        wrapper.layer?.cornerRadius = 8
        wrapper.layer?.borderWidth = 1
        wrapper.layer?.borderColor = Colors.borderLight.cgColor
        wrapper.layer?.backgroundColor = Colors.surfacePrimary.cgColor

        field.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(field)

        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])

        return wrapper
    }

    @objc private func submitTapped() {
        onSubmit?(usernameField.stringValue, passwordField.stringValue)
        dismissAnimated()
    }

    @objc private func cancelTapped() {
        onCancel?()
        dismissAnimated()
    }

    private func dismissAnimated() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: {
            self.removeFromSuperview()
        })
    }
}

