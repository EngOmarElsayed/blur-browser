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
    var onLinkClicked: ((URL) -> Void)?

    private let contentView = NSView()
    private let closeButton = NSButton()
    private let themeButton = NSButton()
    private let readerWebView: WKWebView
    private let article: ReaderArticle
    private let articleURL: URL?
    private var currentTheme: ReaderTheme
    private var currentFont: ReaderFont

    init(article: ReaderArticle, baseURL: URL?) {
        let config = WKWebViewConfiguration()
        self.readerWebView = WKWebView(frame: .zero, configuration: config)
        self.article = article
        self.articleURL = baseURL
        self.currentTheme = ReaderModeService.currentTheme
        self.currentFont = ReaderModeService.currentFont
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true
        // Outer chrome — colored to match the theme's background so there's no
        // visual seam between chrome and article area.
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
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        // Appearance button (top-right) — theme + font picker
        themeButton.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Reader Appearance")
        themeButton.isBordered = false
        themeButton.bezelStyle = .circular
        themeButton.target = self
        themeButton.action = #selector(themeTapped)
        themeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(themeButton)

        // Content container
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 10
        contentView.layer?.masksToBounds = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)

        // Reader web view — intercept link clicks via navigation delegate
        readerWebView.setValue(false, forKey: "drawsBackground")
        readerWebView.navigationDelegate = self
        readerWebView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(readerWebView)

        // Layout
        let chromeEdge: CGFloat = 12
        let topEdge: CGFloat = 40

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

            themeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            themeButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            themeButton.widthAnchor.constraint(equalToConstant: 24),
            themeButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Apply the initial theme (colors + load HTML)
        applyTheme(currentTheme)
    }

    // MARK: - Theme + Font

    private func applyTheme(_ theme: ReaderTheme) {
        currentTheme = theme
        ReaderModeService.currentTheme = theme

        // Outer chrome background matches the theme's article background
        layer?.backgroundColor = theme.backgroundNSColor.cgColor
        contentView.layer?.backgroundColor = theme.backgroundNSColor.cgColor

        // Tint the chrome buttons to the theme's foreground so they stay readable
        closeButton.contentTintColor = theme.foregroundNSColor.withAlphaComponent(0.75)
        themeButton.contentTintColor = theme.foregroundNSColor.withAlphaComponent(0.75)

        reloadReaderHTML()
    }

    private func applyFont(_ font: ReaderFont) {
        currentFont = font
        ReaderModeService.currentFont = font
        reloadReaderHTML()
    }

    private func reloadReaderHTML() {
        let html = ReaderModeService.renderHTML(
            for: article,
            theme: currentTheme,
            font: currentFont
        )
        readerWebView.loadHTMLString(html, baseURL: articleURL)
    }

    @objc private func themeTapped() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = ReaderAppearancePickerViewController(
            currentTheme: currentTheme,
            currentFont: currentFont,
            onPickTheme: { [weak self] theme in
                self?.applyTheme(theme)
            },
            onPickFont: { [weak self] font in
                self?.applyFont(font)
            }
        )
        popover.show(
            relativeTo: themeButton.bounds,
            of: themeButton,
            preferredEdge: .maxY
        )
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

// MARK: - WKNavigationDelegate

extension ReaderModeView: WKNavigationDelegate {

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url {

            if isSameDocumentAnchor(url: url, in: webView) {
                decisionHandler(.allow)
                return
            }

            onLinkClicked?(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    private func isSameDocumentAnchor(url: URL, in webView: WKWebView) -> Bool {
        guard let currentURL = webView.url else { return false }
        var stripped = URLComponents(url: url, resolvingAgainstBaseURL: false)
        stripped?.fragment = nil
        var currentStripped = URLComponents(url: currentURL, resolvingAgainstBaseURL: false)
        currentStripped?.fragment = nil
        return stripped?.url == currentStripped?.url && url.fragment != nil
    }
}

// MARK: - Appearance Picker Popover (Theme + Font)

@MainActor
private final class ReaderAppearancePickerViewController: NSViewController {

    private var currentTheme: ReaderTheme
    private var currentFont: ReaderFont
    private let onPickTheme: (ReaderTheme) -> Void
    private let onPickFont: (ReaderFont) -> Void

    private var themeSwatches: [ThemeSwatchButton] = []
    private var fontSwatches: [FontSwatchButton] = []

    init(
        currentTheme: ReaderTheme,
        currentFont: ReaderFont,
        onPickTheme: @escaping (ReaderTheme) -> Void,
        onPickFont: @escaping (ReaderFont) -> Void
    ) {
        self.currentTheme = currentTheme
        self.currentFont = currentFont
        self.onPickTheme = onPickTheme
        self.onPickFont = onPickFont
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 136))
        container.wantsLayer = true

        // Theme row
        let themeRow = NSStackView()
        themeRow.orientation = .horizontal
        themeRow.spacing = 10
        themeRow.translatesAutoresizingMaskIntoConstraints = false
        for theme in ReaderTheme.allCases {
            let swatch = ThemeSwatchButton(theme: theme, isSelected: theme == currentTheme)
            swatch.target = self
            swatch.action = #selector(themeTapped(_:))
            themeSwatches.append(swatch)
            themeRow.addArrangedSubview(swatch)
        }

        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        // Font row — each swatch has a label stacked underneath
        let fontRow = NSStackView()
        fontRow.orientation = .horizontal
        fontRow.alignment = .top
        fontRow.spacing = 10
        fontRow.translatesAutoresizingMaskIntoConstraints = false
        for font in ReaderFont.allCases {
            let swatch = FontSwatchButton(font: font, isSelected: font == currentFont)
            swatch.target = self
            swatch.action = #selector(fontTapped(_:))
            fontSwatches.append(swatch)

            let label = NSTextField(labelWithString: font.displayName)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center

            let column = NSStackView(views: [swatch, label])
            column.orientation = .vertical
            column.alignment = .centerX
            column.spacing = 4
            fontRow.addArrangedSubview(column)
        }

        let outer = NSStackView(views: [themeRow, divider, fontRow])
        outer.orientation = .vertical
        outer.alignment = .centerX
        outer.spacing = 12
        outer.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        outer.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(outer)

        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            outer.topAnchor.constraint(equalTo: container.topAnchor),
            outer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            divider.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -28),
        ])

        self.view = container
    }

    @objc private func themeTapped(_ sender: ThemeSwatchButton) {
        currentTheme = sender.theme
        onPickTheme(sender.theme)
        // Update visual selection without closing the popover
        for swatch in themeSwatches {
            swatch.updateSelected(swatch.theme == sender.theme)
        }
    }

    @objc private func fontTapped(_ sender: FontSwatchButton) {
        currentFont = sender.readerFont
        onPickFont(sender.readerFont)
        for swatch in fontSwatches {
            swatch.updateSelected(swatch.readerFont == sender.readerFont)
        }
    }
}

// MARK: - Theme Swatch Button

@MainActor
private final class ThemeSwatchButton: NSButton {

    let theme: ReaderTheme

    init(theme: ReaderTheme, isSelected: Bool) {
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        setup(isSelected: isSelected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup(isSelected: Bool) {
        title = "Aa"
        isBordered = false
        bezelStyle = .shadowlessSquare
        wantsLayer = true

        layer?.backgroundColor = theme.backgroundNSColor.cgColor
        layer?.cornerRadius = 18
        updateSelected(isSelected)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(
            string: "Aa",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: theme.foregroundNSColor,
                .paragraphStyle: paragraph,
            ]
        )

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func updateSelected(_ selected: Bool) {
        layer?.borderWidth = selected ? 2 : 1
        layer?.borderColor = selected
            ? Colors.accentPrimary.cgColor
            : NSColor.black.withAlphaComponent(0.15).cgColor
    }
}

// MARK: - Font Swatch Button

@MainActor
private final class FontSwatchButton: NSButton {

    let readerFont: ReaderFont

    init(font: ReaderFont, isSelected: Bool) {
        self.readerFont = font
        super.init(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        setup(isSelected: isSelected)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup(isSelected: Bool) {
        title = readerFont.previewLabel
        isBordered = false
        bezelStyle = .shadowlessSquare
        wantsLayer = true

        // Neutral light background so the font preview stands out
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 18
        updateSelected(isSelected)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        attributedTitle = NSAttributedString(
            string: readerFont.previewLabel,
            attributes: [
                .font: readerFont.previewNSFont,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph,
            ]
        )

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 36),
            heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func updateSelected(_ selected: Bool) {
        layer?.borderWidth = selected ? 2 : 1
        layer?.borderColor = selected
            ? Colors.accentPrimary.cgColor
            : NSColor.black.withAlphaComponent(0.15).cgColor
    }
}
