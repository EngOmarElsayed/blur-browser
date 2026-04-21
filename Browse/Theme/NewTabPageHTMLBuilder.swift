import Foundation

/// Generates the HTML + inline CSS for the `blur://newtab` page.
/// The page is intentionally minimal: a full-bleed wallpaper picked at random
/// from the active theme's set, and nothing else. The user types into the
/// existing address bar rather than an in-page field.
/// Wallpapers are referenced via the `blur-image://` scheme so the web view
/// loads them from the app bundle.
enum NewTabPageHTMLBuilder {

    static func html(for theme: Theme) -> String {
        // Pick a random wallpaper from the theme's set
        let wallpaper = theme.wallpaperNames.randomElement() ?? theme.wallpaperNames[0]
        let wallpaperURL = "blur-image://\(wallpaper).jpg"
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
            .bg {
              position: fixed; inset: 0;
              background: url('\(wallpaperURL)') center/cover no-repeat;
            }
          </style>
        </head>
        <body>
          <div class="bg"></div>
        </body>
        </html>
        """
    }
}
