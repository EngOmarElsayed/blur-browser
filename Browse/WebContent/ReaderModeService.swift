import Foundation
import WebKit

/// Article extracted from a web page by Mozilla Readability.js
struct ReaderArticle {
    let title: String
    let byline: String?
    let contentHTML: String
    let excerpt: String?
    let siteName: String?
    let length: Int
}

/// Font choices for the reader view.
enum ReaderFont: String, CaseIterable {
    case newYork    // default serif
    case georgia    // alternate serif
    case system     // SF Pro (sans-serif)
    case mono       // SF Mono

    /// Display label for the font picker preview ("Aa")
    var previewLabel: String { "Aa" }

    /// Human-readable name shown under each swatch
    var displayName: String {
        switch self {
        case .newYork: return "New York"
        case .georgia: return "Georgia"
        case .system:  return "System"
        case .mono:    return "Mono"
        }
    }

    /// CSS font-family for body text
    var bodyCSS: String {
        switch self {
        case .newYork: return "\"New York\", \"SF Pro Display\", Georgia, serif"
        case .georgia: return "Georgia, \"Times New Roman\", serif"
        case .system:  return "-apple-system, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        case .mono:    return "\"SF Mono\", Menlo, Consolas, monospace"
        }
    }

    /// CSS font-family for headings
    var headingCSS: String {
        switch self {
        case .newYork: return "\"New York\", \"SF Pro Display\", Georgia, serif"
        case .georgia: return "Georgia, \"Times New Roman\", serif"
        case .system:  return "-apple-system, \"SF Pro Display\", \"Helvetica Neue\", sans-serif"
        case .mono:    return "\"SF Mono\", Menlo, Consolas, monospace"
        }
    }

    /// NSFont used for the swatch preview
    var previewNSFont: NSFont {
        switch self {
        case .newYork:
            return NSFont(name: "New York", size: 14)
                ?? NSFont.systemFont(ofSize: 14, weight: .semibold)
        case .georgia:
            return NSFont(name: "Georgia", size: 14)
                ?? NSFont.systemFont(ofSize: 14, weight: .semibold)
        case .system:
            return NSFont.systemFont(ofSize: 14, weight: .semibold)
        case .mono:
            return NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
        }
    }
}

/// Color themes for the reader view. Safari-style.
enum ReaderTheme: String, CaseIterable {
    case light
    case sepia
    case gray
    case dark

    /// Background hex for the inner article area
    var backgroundHex: String {
        switch self {
        case .light: return "#FFFFFF"
        case .sepia: return "#F2E8D5"
        case .gray:  return "#4A4A4A"
        case .dark:  return "#1A1A1A"
        }
    }

    /// Primary text hex
    var foregroundHex: String {
        switch self {
        case .light: return "#1A1A1A"
        case .sepia: return "#3B2F1E"
        case .gray:  return "#E8E8E8"
        case .dark:  return "#D6D6D6"
        }
    }

    /// Secondary (muted) text hex
    var secondaryHex: String {
        switch self {
        case .light: return "#5A5E6B"
        case .sepia: return "#6B5B3A"
        case .gray:  return "#B0B0B0"
        case .dark:  return "#9CA3AF"
        }
    }

    /// Link color
    var accentHex: String {
        switch self {
        case .light: return "#6366F1"
        case .sepia: return "#9C6B1E"
        case .gray:  return "#82CFFF"
        case .dark:  return "#7DB3FF"
        }
    }

    /// Divider/border
    var borderHex: String {
        switch self {
        case .light: return "#E5E7EB"
        case .sepia: return "#D8CDB3"
        case .gray:  return "#5E5E5E"
        case .dark:  return "#2E2E2E"
        }
    }

    /// Code block background
    var codeBackgroundHex: String {
        switch self {
        case .light: return "#F6F7FA"
        case .sepia: return "#E8DEC5"
        case .gray:  return "#3A3A3A"
        case .dark:  return "#2A2A2A"
        }
    }

    /// NSColor equivalent of `backgroundHex` — used for the reader panel's
    /// outer chrome so it matches the inner article background.
    var backgroundNSColor: NSColor {
        NSColor(hex: backgroundHex)
    }

    /// NSColor equivalent of `foregroundHex`
    var foregroundNSColor: NSColor {
        NSColor(hex: foregroundHex)
    }
}

@MainActor
enum ReaderModeService {

    /// Checks if the current page has enough content to be worth showing in reader mode.
    static func isReaderable(webView: WKWebView) async -> Bool {
        guard let readerableSource = loadScript("Readability-readerable") else { return false }

        let script = """
        (function() {
            \(readerableSource)
            try {
                return isProbablyReaderable(document);
            } catch (e) {
                return false;
            }
        })();
        """

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: (result as? Bool) ?? false)
            }
        }
    }

    /// Parses the current page with Readability and returns the article.
    static func parseArticle(webView: WKWebView) async -> ReaderArticle? {
        guard let readabilitySource = loadScript("Readability") else { return nil }

        // Readability mutates the DOM, so we clone the document first
        let script = """
        (function() {
            \(readabilitySource)
            try {
                var documentClone = document.cloneNode(true);
                var article = new Readability(documentClone).parse();
                if (!article) return null;
                return {
                    title: article.title || "",
                    byline: article.byline || "",
                    content: article.content || "",
                    excerpt: article.excerpt || "",
                    siteName: article.siteName || "",
                    length: article.length || 0
                };
            } catch (e) {
                return null;
            }
        })();
        """

        return await withCheckedContinuation { (continuation: CheckedContinuation<ReaderArticle?, Never>) in
            webView.evaluateJavaScript(script) { result, _ in
                guard let dict = result as? [String: Any],
                      let title = dict["title"] as? String,
                      let content = dict["content"] as? String
                else {
                    continuation.resume(returning: nil)
                    return
                }
                let article = ReaderArticle(
                    title: title,
                    byline: (dict["byline"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    contentHTML: content,
                    excerpt: (dict["excerpt"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    siteName: (dict["siteName"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                    length: dict["length"] as? Int ?? 0
                )
                continuation.resume(returning: article)
            }
        }
    }

    /// Builds a styled HTML page from the extracted article.
    static func renderHTML(
        for article: ReaderArticle,
        theme: ReaderTheme = .light,
        font: ReaderFont = .newYork
    ) -> String {
        let title = article.title.htmlEscaped
        let byline = article.byline?.htmlEscaped ?? ""
        let siteName = article.siteName?.htmlEscaped ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(title)</title>
            <style>
                :root {
                    --fg: \(theme.foregroundHex);
                    --fg-secondary: \(theme.secondaryHex);
                    --accent: \(theme.accentHex);
                    --bg: \(theme.backgroundHex);
                    --border: \(theme.borderHex);
                    --code-bg: \(theme.codeBackgroundHex);
                }
                * { box-sizing: border-box; }
                body {
                    font-family: \(font.bodyCSS);
                    font-size: 18px;
                    line-height: 1.7;
                    color: var(--fg);
                    background: var(--bg);
                    margin: 0;
                    padding: 32px 40px 64px;
                    max-width: 720px;
                    margin: 0 auto;
                    -webkit-font-smoothing: antialiased;
                }
                .site-name {
                    font-size: 13px;
                    color: var(--fg-secondary);
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    margin-bottom: 8px;
                }
                h1.article-title {
                    font-family: \(font.headingCSS);
                    font-size: 34px;
                    line-height: 1.2;
                    font-weight: 700;
                    margin: 8px 0 12px;
                    color: var(--fg);
                }
                .byline {
                    font-size: 14px;
                    color: var(--fg-secondary);
                    margin-bottom: 32px;
                    padding-bottom: 16px;
                    border-bottom: 1px solid var(--border);
                }
                .content { font-size: 18px; }
                .content p { margin: 0 0 20px; }
                .content h1, .content h2, .content h3 {
                    font-family: \(font.headingCSS);
                    font-weight: 700;
                    line-height: 1.3;
                    margin-top: 32px;
                    margin-bottom: 12px;
                }
                .content h1 { font-size: 28px; }
                .content h2 { font-size: 24px; }
                .content h3 { font-size: 20px; }
                .content a { color: var(--accent); text-decoration: underline; text-underline-offset: 2px; }
                .content blockquote {
                    border-left: 3px solid var(--accent);
                    padding: 0 0 0 16px;
                    margin: 20px 0;
                    color: var(--fg-secondary);
                    font-style: italic;
                }
                .content img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 8px;
                    margin: 16px 0;
                }
                .content figure { margin: 20px 0; }
                .content figcaption {
                    font-size: 14px;
                    color: var(--fg-secondary);
                    text-align: center;
                    margin-top: 8px;
                }
                .content pre {
                    background: var(--code-bg);
                    padding: 16px;
                    border-radius: 8px;
                    overflow-x: auto;
                    font-size: 14px;
                }
                .content code {
                    background: var(--code-bg);
                    padding: 2px 6px;
                    border-radius: 4px;
                    font-size: 15px;
                }
                .content pre code { background: none; padding: 0; }
                .content ul, .content ol { padding-left: 24px; margin-bottom: 20px; }
                .content li { margin-bottom: 8px; }
                .content hr {
                    border: none;
                    border-top: 1px solid var(--border);
                    margin: 32px 0;
                }
            </style>
        </head>
        <body>
            \(siteName.isEmpty ? "" : "<div class=\"site-name\">\(siteName)</div>")
            <h1 class="article-title">\(title)</h1>
            \(byline.isEmpty ? "" : "<div class=\"byline\">\(byline)</div>")
            <div class="content">\(article.contentHTML)</div>
        </body>
        </html>
        """
    }

    // MARK: - Theme + Font Persistence

    private static let themeKey = "readerMode.theme"
    private static let fontKey = "readerMode.font"

    /// The currently selected reader theme (persisted across launches).
    static var currentTheme: ReaderTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: themeKey),
                  let theme = ReaderTheme(rawValue: raw)
            else { return .light }
            return theme
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: themeKey)
        }
    }

    /// The currently selected reader font (persisted across launches).
    static var currentFont: ReaderFont {
        get {
            guard let raw = UserDefaults.standard.string(forKey: fontKey),
                  let font = ReaderFont(rawValue: raw)
            else { return .newYork }
            return font
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: fontKey)
        }
    }

    // MARK: - Helpers

    private static func loadScript(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url)
        else {
            print("[ReaderModeService] Failed to load \(name).js")
            return nil
        }
        return source
    }
}

// MARK: - String Helpers

private extension String {
    var htmlEscaped: String {
        self.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
