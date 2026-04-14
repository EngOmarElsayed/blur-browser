import WebKit

@MainActor
final class FindInPageController {
    private weak var webView: WKWebView?
    private var currentQuery: String = ""
    var matchCount: Int = 0
    var currentMatch: Int = 0
    var onMatchUpdate: ((Int, Int) -> Void)?

    init(webView: WKWebView?) {
        self.webView = webView
    }

    func search(for text: String) {
        guard let webView, !text.isEmpty else {
            clearHighlights()
            return
        }
        currentQuery = text

        let config = WKFindConfiguration()
        config.wraps = true
        config.caseSensitive = false

        webView.find(text, configuration: config) { [weak self] result in
            guard let self else { return }
            self.matchCount = result.matchFound ? -1 : 0 // WKFindResult doesn't give count directly
            if result.matchFound {
                // Use JS to get count
                self.getMatchCount(for: text)
            } else {
                self.matchCount = 0
                self.currentMatch = 0
                self.onMatchUpdate?(0, 0)
            }
        }
    }

    func findNext() {
        guard let webView, !currentQuery.isEmpty else { return }
        let config = WKFindConfiguration()
        config.wraps = true
        config.caseSensitive = false
        webView.find(currentQuery, configuration: config) { [weak self] result in
            guard let self, result.matchFound else { return }
            self.currentMatch = min(self.currentMatch + 1, self.matchCount)
            if self.currentMatch > self.matchCount { self.currentMatch = 1 }
            self.onMatchUpdate?(self.currentMatch, self.matchCount)
        }
    }

    func findPrevious() {
        guard let webView, !currentQuery.isEmpty else { return }
        let config = WKFindConfiguration()
        config.wraps = true
        config.caseSensitive = false
        config.backwards = true
        webView.find(currentQuery, configuration: config) { [weak self] result in
            guard let self, result.matchFound else { return }
            self.currentMatch = max(self.currentMatch - 1, 1)
            if self.currentMatch < 1 { self.currentMatch = self.matchCount }
            self.onMatchUpdate?(self.currentMatch, self.matchCount)
        }
    }

    func clearHighlights() {
        webView?.evaluateJavaScript("window.getSelection().removeAllRanges()")
        matchCount = 0
        currentMatch = 0
        currentQuery = ""
        onMatchUpdate?(0, 0)
    }

    private func getMatchCount(for text: String) {
        let escaped = text.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (() => {
            const body = document.body.innerText || '';
            const regex = new RegExp('\(escaped)', 'gi');
            const matches = body.match(regex);
            return matches ? matches.length : 0;
        })()
        """
        webView?.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            if let count = result as? Int {
                self.matchCount = count
                self.currentMatch = count > 0 ? 1 : 0
                self.onMatchUpdate?(self.currentMatch, count)
            }
        }
    }
}
