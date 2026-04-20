import AppKit
import WebKit

/// Full-screen overlay that displays an article in reader mode.
/// Sits on top of the current web content — has chrome edge, close button,
/// and supports ESC to dismiss.
@MainActor
final class ReaderModeView: NSView {

    // MARK: - Size — change these to resize the reader panel
    static let panelWidth: CGFloat = 780
    static let panelHeight: CGFloat = 640

    var onClose: (() -> Void)?

    private let chromeView = NSView()
    private let contentView = NSView()
    private let closeButton = NSButton()
    private let readerWebView: WKWebView
    private let articleHTML: String
    private let articleURL: URL?

    init(article: ReaderArticle, baseURL: URL?) {
        let config = WKWebViewConfiguration()
        self.readerWebView = WKWebView(frame: .zero, configuration: config)
        self.articleHTML = ReaderModeService.renderHTML(for: article)
        self.articleURL = baseURL
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        // Chrome-colored outer background with rounded corners + shadow so the
        // panel visually floats above the web page behind it.
        layer?.backgroundColor = Colors.chromeBg.cgColor
        layer?.cornerRadius = 14
        layer?.masksToBounds = false
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.22).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        layer?.shadowRadius = 24
        layer?.shadowOpacity = 1

        // Close button (top-left)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Reader")
        closeButton.isBordered = false
        closeButton.bezelStyle = .circular
        closeButton.contentTintColor = Colors.foregroundSecondary
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        // Content container (rounded corners, white background)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = Colors.surfacePrimary.cgColor
        contentView.layer?.cornerRadius = 10
        contentView.layer?.masksToBounds = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        // Reader web view
        readerWebView.setValue(false, forKey: "drawsBackground")
        readerWebView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(readerWebView)

        // Layout — chrome edge all around, matching MainSplitViewController (12pt)
        let chromeEdge: CGFloat = 12
        let topEdge: CGFloat = 40 // extra room for the close button

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: chromeEdge),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -chromeEdge),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: topEdge),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -chromeEdge),

            readerWebView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            readerWebView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            readerWebView.topAnchor.constraint(equalTo: contentView.topAnchor),
            readerWebView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Load article
        readerWebView.loadHTMLString(articleHTML, baseURL: articleURL)
    }

    // MARK: - Key Handling (ESC)

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        // ESC key = 53
        if event.keyCode == 53 {
            closeTapped()
            return
        }
        super.keyDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
