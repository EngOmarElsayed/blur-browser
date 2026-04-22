import AppKit

/// Centered alert-style panel shown before a download begins, asking the user
/// to allow or deny. Matches the visual style of AuthenticationDialogView.
@MainActor
final class DownloadConfirmationView: NSView {

    static let panelWidth: CGFloat = 360
    static let panelHeight: CGFloat = 210

    var onAllow: (() -> Void)?
    var onDeny: (() -> Void)?

    init(filename: String, host: String?, expectedSize: Int64?) {
        super.init(frame: .zero)
        setup(filename: filename, host: host, expectedSize: expectedSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup(filename: String, host: String?, expectedSize: Int64?) {
        wantsLayer = true
        layer?.backgroundColor = Colors.chromeBg.cgColor
        layer?.cornerRadius = 14
        layer?.borderColor = Colors.borderLight.cgColor
        layer?.borderWidth = 1

        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.18).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowRadius = 20
        layer?.shadowOpacity = 1

        // Icon — file-type icon if we can derive it, else generic download arrow
        let iconView = NSImageView()
        iconView.image = iconImage(for: filename)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = Colors.foregroundPrimary

        // Title
        let titleLabel = NSTextField(labelWithString: "Download \"\(filename)\"?")
        titleLabel.font = NSFont(name: Typography.fontFamily, size: 14)
            ?? .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Colors.foregroundPrimary
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 2

        // Subtitle — "From <host>"
        let subtitleText: String = {
            if let host, !host.isEmpty { return "From \(host)" }
            return "From an unknown source"
        }()
        let subtitleLabel = NSTextField(labelWithString: subtitleText)
        subtitleLabel.font = NSFont(name: Typography.fontFamily, size: 12)
            ?? .systemFont(ofSize: 12)
        subtitleLabel.textColor = Colors.foregroundSecondary
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byTruncatingMiddle

        // Optional size hint
        let sizeLabel: NSTextField?
        if let size = expectedSize, size > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let label = NSTextField(labelWithString: "Size: \(formatter.string(fromByteCount: size))")
            label.font = NSFont(name: Typography.fontFamily, size: 11)
                ?? .systemFont(ofSize: 11)
            label.textColor = Colors.foregroundSecondary
            label.alignment = .center
            sizeLabel = label
        } else {
            sizeLabel = nil
        }

        // Buttons
        let denyButton = NSButton(title: "Don't Allow", target: self, action: #selector(denyTapped))
        denyButton.bezelStyle = .rounded
        denyButton.controlSize = .large
        denyButton.keyEquivalent = "\u{1b}" // Escape
        denyButton.attributedTitle = NSAttributedString(
            string: "Don't Allow",
            attributes: [
                .foregroundColor: Colors.accentPrimary,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
        )

        let allowButton = NSButton(title: "Download", target: self, action: #selector(allowTapped))
        allowButton.bezelStyle = .rounded
        allowButton.controlSize = .large
        allowButton.keyEquivalent = "\r" // Enter

        let buttonStack = NSStackView(views: [denyButton, allowButton])
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8

        // Layout
        var rows: [NSView] = [iconView, titleLabel, subtitleLabel]
        if let sizeLabel { rows.append(sizeLabel) }
        rows.append(buttonStack)
        for v in rows {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            buttonStack.heightAnchor.constraint(equalToConstant: 28),
        ])

        if let sizeLabel {
            NSLayoutConstraint.activate([
                sizeLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 4),
                sizeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                sizeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            ])
        }
    }

    private func iconImage(for filename: String) -> NSImage? {
        let ext = (filename as NSString).pathExtension
        if !ext.isEmpty {
            let icon = NSWorkspace.shared.icon(forFileType: ext)
            return icon
        }
        return NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Download")
    }

    @objc private func allowTapped() {
        onAllow?()
        dismissAnimated()
    }

    @objc private func denyTapped() {
        onDeny?()
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
