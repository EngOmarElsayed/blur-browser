import AppKit

/// A centered alert-style panel that appears over the web content
/// when a website requests camera, microphone, or location access.
@MainActor
final class PermissionBannerView: NSView {

    enum PermissionType {
        case camera
        case microphone
        case cameraAndMicrophone
        case location

        var icon: String {
            switch self {
            case .camera: "camera.fill"
            case .microphone: "mic.fill"
            case .cameraAndMicrophone: "video.fill"
            case .location: "location.fill"
            }
        }

        var label: String {
            switch self {
            case .camera: "camera"
            case .microphone: "microphone"
            case .cameraAndMicrophone: "camera and microphone"
            case .location: "location"
            }
        }

        /// Map to SitePermissionType(s) for storage
        var sitePermissionTypes: [SitePermissionType] {
            switch self {
            case .camera:              [.camera]
            case .microphone:          [.microphone]
            case .cameraAndMicrophone: [.camera, .microphone]
            case .location:            [.location]
            }
        }
    }

    static let panelWidth: CGFloat = 340
    static let panelHeight: CGFloat = 160

    var onAllow: (() -> Void)?
    var onAlwaysAllow: (() -> Void)?
    var onDeny: (() -> Void)?

    init(type: PermissionType, host: String) {
        super.init(frame: .zero)
        setup(type: type, host: host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup(type: PermissionType, host: String) {
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
        iconView.image = NSImage(systemSymbolName: type.icon, accessibilityDescription: nil)
        iconView.contentTintColor = Colors.foregroundPrimary
        iconView.imageScaling = .scaleProportionallyUpOrDown

        // Title
        let titleLabel = NSTextField(labelWithString: "Allow \"\(host)\" to use your \(type.label)?")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Colors.foregroundPrimary
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.alignment = .center

        // Buttons
        let denyButton = NSButton(title: "Don't Allow", target: self, action: #selector(denyTapped))
        denyButton.bezelStyle = .rounded
        denyButton.controlSize = .large
        denyButton.keyEquivalent = "\u{1b}"

        let allowButton = NSButton(title: "Allow Once", target: self, action: #selector(allowTapped))
        allowButton.bezelStyle = .rounded
        allowButton.controlSize = .large

        let alwaysAllowButton = NSButton(title: "Always Allow", target: self, action: #selector(alwaysAllowTapped))
        alwaysAllowButton.bezelStyle = .rounded
        alwaysAllowButton.controlSize = .large
        alwaysAllowButton.keyEquivalent = "\r"

        // Button row
        let buttonStack = NSStackView(views: [denyButton, allowButton, alwaysAllowButton])
        buttonStack.distribution = .fillEqually
        buttonStack.spacing = 8

        // Layout
        for v in [iconView, titleLabel, buttonStack] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }

        NSLayoutConstraint.activate([
            // Icon centered at top
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            // Title below icon
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            // Buttons at bottom
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            buttonStack.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    @objc private func allowTapped() {
        onAllow?()
        dismissAnimated()
    }

    @objc private func alwaysAllowTapped() {
        onAlwaysAllow?()
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
