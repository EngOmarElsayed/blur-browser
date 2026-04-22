import Foundation

/// Generates the HTML + inline CSS for the `blur://newtab` page.
/// The page is intentionally minimal: a full-bleed wallpaper picked at random
/// from the active theme's set, and nothing else. The user types into the
/// existing address bar rather than an in-page field.
///
/// Performance note: the wallpaper is inlined as a base64 data URL so the
/// browser doesn't make a second scheme-handler roundtrip to fetch the image.
/// Image bytes are cached in memory after the first read so subsequent
/// new-tab loads skip disk I/O entirely.
enum NewTabPageHTMLBuilder {

    // MARK: - In-memory wallpaper cache

    /// Base64-encoded `data:` URL per wallpaper name. Populated lazily on first
    /// request for each wallpaper. Image files are ~300KB–1MB so the worst-case
    /// footprint is bounded by the total number of wallpapers across themes.
    private static var base64CacheLock = NSLock()
    private static var base64Cache: [String: String] = [:]

    private static func cachedDataURL(for wallpaper: String) -> String? {
        base64CacheLock.lock()
        if let cached = base64Cache[wallpaper] {
            base64CacheLock.unlock()
            return cached
        }
        base64CacheLock.unlock()

        guard let fileURL = Bundle.main.url(forResource: wallpaper, withExtension: "jpg"),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        let dataURL = "data:image/jpeg;base64,\(data.base64EncodedString())"

        base64CacheLock.lock()
        base64Cache[wallpaper] = dataURL
        base64CacheLock.unlock()

        return dataURL
    }

    static func html(for theme: Theme) -> String {
        // Pick a random wallpaper from the theme's set
        let wallpaper = theme.wallpaperNames.randomElement() ?? theme.wallpaperNames[0]
        // Prefer the inlined data URL (no second scheme-handler roundtrip).
        // Fall back to the blur-image:// scheme if the bundle read fails.
        let wallpaperURL = cachedDataURL(for: wallpaper) ?? "blur-image://\(wallpaper).jpg"
        let colorScheme = theme.isDark ? "dark" : "light"

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="color-scheme" content="\(colorScheme)">
          <title>New Tab</title>
          <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            html, body {
              width: 100%;
              height: 100%;
              overflow: hidden;
              background: \(theme.chromeHex);
            }
            /* The wallpaper fills the whole viewport while keeping its native
               aspect ratio — `object-fit: cover` scales proportionally and
               crops overflow on the short axis. The ratio is never distorted. */
            .bg {
              position: fixed;
              inset: 0;
              width: 100%;
              height: 100%;
              object-fit: cover;
              object-position: center center;
              display: block;
              user-select: none;
              -webkit-user-drag: none;
            }
          </style>
        </head>
        <body>
          <img class="bg" src="\(wallpaperURL)" alt="">
        </body>
        </html>
        """
    }
}
