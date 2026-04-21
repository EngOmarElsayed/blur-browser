import Foundation
import WebKit

/// Serves `blur://newtab` (themed HTML) and `blur-image://<name>.jpg` (bundled wallpaper).
@MainActor
final class BlurSchemeHandler: NSObject, WKURLSchemeHandler {

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        Task { await handle(urlSchemeTask) }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    // MARK: - Routing

    private func handle(_ task: any WKURLSchemeTask) async {
        guard let url = task.request.url else {
            fail(task, reason: "no url")
            return
        }

        switch url.scheme {
        case "blur":
            serveNewTab(task, url: url)
        case "blur-image":
            serveImage(task, url: url)
        default:
            fail(task, reason: "unsupported scheme: \(url.scheme ?? "nil")")
        }
    }

    // MARK: - blur://newtab

    private func serveNewTab(_ task: any WKURLSchemeTask, url: URL) {
        let theme = ThemeStore.shared.current
        let html = NewTabPageHTMLBuilder.html(for: theme)
        guard let data = html.data(using: .utf8) else {
            fail(task, reason: "encoding")
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/html; charset=utf-8",
                "Content-Length": "\(data.count)",
                "Cache-Control": "no-store"
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    // MARK: - blur-image://<name>.jpg

    private func serveImage(_ task: any WKURLSchemeTask, url: URL) {
        // URL host carries the filename (WebKit parses `blur-image://name.jpg` with host = "name.jpg")
        let filename = (url.host ?? "") + url.path
        let cleanName = filename.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Split into name + extension
        guard let dotRange = cleanName.range(of: ".", options: .backwards) else {
            fail(task, reason: "no extension in \(cleanName)")
            return
        }
        let name = String(cleanName[..<dotRange.lowerBound])
        let ext = String(cleanName[dotRange.upperBound...])

        // Images are bundled at the root of Resources/ by the synchronized-folder
        // reference on the `Browse/images/` folder, so no subdirectory is passed.
        guard let fileURL = Bundle.main.url(forResource: name, withExtension: ext),
              let data = try? Data(contentsOf: fileURL) else {
            fail(task, reason: "not found: \(cleanName)")
            return
        }

        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType(forExtension: ext),
                "Content-Length": "\(data.count)",
                "Cache-Control": "public, max-age=86400"
            ]
        )!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "webp":        return "image/webp"
        case "heic":        return "image/heic"
        default:            return "application/octet-stream"
        }
    }

    private func fail(_ task: any WKURLSchemeTask, reason: String) {
        task.didFailWithError(NSError(
            domain: "BlurSchemeHandler",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: reason]
        ))
    }
}
