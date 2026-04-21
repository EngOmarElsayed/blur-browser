import Foundation

/// Generates the HTML + inline CSS for the `blur://newtab` page.
/// Colors are interpolated from the passed-in Theme; the wallpaper filename
/// is referenced via the `blur-image://` scheme so the web view loads it
/// from the app bundle.
enum NewTabPageHTMLBuilder {

    static func html(for theme: Theme, searchPlaceholder: String = "Search or enter URL") -> String {
        // Pick a random wallpaper from the theme's set
        let wallpaper = theme.wallpaperNames.randomElement() ?? theme.wallpaperNames[0]
        let wallpaperURL = "blur-image://\(wallpaper).jpg"
        let greeting = greetingForCurrentHour()
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
              font-family: -apple-system, 'Inter', system-ui, sans-serif;
              background: \(theme.chromeHex);
            }
            .bg {
              position: fixed; inset: 0;
              background: url('\(wallpaperURL)') center/cover no-repeat;
              z-index: 0;
            }
            .scrim {
              position: fixed; inset: 0;
              background: linear-gradient(180deg, rgba(0,0,0,0.15) 0%, rgba(0,0,0,0.35) 100%);
              z-index: 1;
            }
            .content {
              position: relative; z-index: 2;
              height: 100%;
              display: flex; flex-direction: column;
              align-items: center; justify-content: center;
              gap: 24px;
            }
            .greeting {
              color: rgba(255,255,255,0.95);
              font-size: 32px;
              font-weight: 500;
              text-shadow: 0 2px 8px rgba(0,0,0,0.35);
              letter-spacing: -0.01em;
            }
            .search-wrap {
              position: relative;
              width: min(560px, 80vw);
            }
            input.search {
              width: 100%;
              height: 52px;
              border-radius: 14px;
              border: 1px solid rgba(255,255,255,0.35);
              background: rgba(255,255,255,0.95);
              backdrop-filter: blur(24px);
              -webkit-backdrop-filter: blur(24px);
              padding: 0 20px 0 46px;
              font-size: 15px;
              color: #1a1a1a;
              outline: none;
              box-shadow: 0 8px 32px rgba(0,0,0,0.18);
              font-family: inherit;
            }
            input.search::placeholder { color: rgba(0,0,0,0.45); }
            input.search:focus {
              border-color: rgba(255,255,255,0.6);
              box-shadow: 0 8px 32px rgba(0,0,0,0.22), 0 0 0 3px rgba(255,255,255,0.15);
            }
            .search-icon {
              position: absolute;
              left: 16px; top: 50%;
              transform: translateY(-50%);
              color: rgba(0,0,0,0.45);
              pointer-events: none;
              width: 18px; height: 18px;
            }
          </style>
        </head>
        <body>
          <div class="bg"></div>
          <div class="scrim"></div>
          <div class="content">
            <div class="greeting">\(htmlEscape(greeting))</div>
            <form class="search-wrap" onsubmit="return submitSearch(event)">
              <svg class="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
              <input id="q" class="search" type="text" placeholder="\(htmlEscape(searchPlaceholder))" autocomplete="off" autofocus>
            </form>
          </div>
          <script>
            function submitSearch(e) {
              e.preventDefault();
              const v = document.getElementById('q').value.trim();
              if (!v) return false;
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.newTabSubmit) {
                window.webkit.messageHandlers.newTabSubmit.postMessage(v);
              }
              return false;
            }
            // Ensure input stays focused even if the page gets re-laid-out
            window.addEventListener('load', () => {
              document.getElementById('q').focus();
            });
          </script>
        </body>
        </html>
        """
    }

    private static func greetingForCurrentHour() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:      return "Good night"
        }
    }

    /// Escape HTML special characters so interpolated user-visible text can't
    /// break the surrounding markup. All values interpolated into HTML text
    /// content (not attributes like CSS/URL contexts) should go through this.
    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
