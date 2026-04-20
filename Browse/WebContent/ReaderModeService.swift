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
    static func renderHTML(for article: ReaderArticle) -> String {
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
                    --fg: #1a1a1a;
                    --fg-secondary: #5a5e6b;
                    --accent: #6366f1;
                    --bg: #ffffff;
                    --border: #e5e7eb;
                }
                * { box-sizing: border-box; }
                body {
                    font-family: -apple-system, "SF Pro Text", "Helvetica Neue", sans-serif;
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
                    font-family: "New York", "SF Pro Display", Georgia, serif;
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
                    font-family: "New York", "SF Pro Display", Georgia, serif;
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
                    background: #f6f7fa;
                    padding: 16px;
                    border-radius: 8px;
                    overflow-x: auto;
                    font-size: 14px;
                }
                .content code {
                    background: #f6f7fa;
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
                @media (prefers-color-scheme: dark) {
                    :root {
                        --fg: #e8e8e8;
                        --fg-secondary: #9ca3af;
                        --bg: #1a1a1a;
                        --border: #333;
                    }
                    .content pre, .content code { background: #2a2a2a; }
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
