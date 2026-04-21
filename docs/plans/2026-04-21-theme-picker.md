# Theme Picker Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a user-selectable theme system with 7 curated themes (chrome color + wallpaper set), plus a new tab page that displays a random wallpaper instead of google.com.

**Architecture:** A single `@Observable` `ThemeStore` holds the active theme and persists to UserDefaults. `Colors`/`SettingsColors` in `Constants.swift` become computed properties that resolve through the store. A custom `blur://newtab` URL scheme renders a themed HTML page with a bundled random wallpaper. Re-rendering is driven by the existing 50 ms polling loop in `BrowserWindowController`.

**Tech Stack:** Swift 6 / Swift Concurrency, `@Observable`, AppKit + SwiftUI (hybrid), WKWebView, `WKURLSchemeHandler`, UserDefaults.

**Testing note:** This project has no test target. Each task has a **manual verification** step instead of unit tests. Build with `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build` and run the app to verify. Commit after every passing task.

**Reference design:** `docs/plans/2026-04-21-theme-picker-design.md`

---

## Task 1: Create the `Theme` model and catalog

**Files:**
- Create: `Browse/Theme/Theme.swift`

**Step 1: Create the directory and file**

Run: `mkdir -p /Users/omarelsayed/Desktop/MyAPPs/Browse/Browse/Theme`

Create `Browse/Theme/Theme.swift` with exactly this content:

```swift
import AppKit

// MARK: - Theme ID

enum ThemeID: String, CaseIterable, Identifiable, Sendable, Codable {
    case periwinkle, midnight, sandstone, nordic, rosewood, verdant, graphite

    var id: String { rawValue }

    static var `default`: ThemeID { .periwinkle }
}

// MARK: - Theme

struct Theme: Sendable, Identifiable {
    let id: ThemeID
    let displayName: String
    let mood: String
    let chromeHex: String
    let foregroundHex: String
    let accentHex: String
    let borderHex: String
    let wallpaperNames: [String]
    let isDark: Bool

    var chromeColor: NSColor { NSColor(hex: chromeHex) }
    var foregroundColor: NSColor { NSColor(hex: foregroundHex) }
    var accentColor: NSColor { NSColor(hex: accentHex) }
    var borderColor: NSColor { NSColor(hex: borderHex) }

    /// Slightly-more-saturated version of the chrome color for active tab highlight backgrounds.
    /// Computed as a 20% blend with the accent color.
    var activeTabHighlight: NSColor {
        chromeColor.blended(withFraction: 0.15, of: accentColor) ?? accentColor
    }
}

// MARK: - Catalog

extension Theme {
    static let all: [Theme] = [
        Theme(
            id: .periwinkle,
            displayName: "Periwinkle",
            mood: "Airy sky blue through frosted glass",
            chromeHex: "#92B4F4",
            foregroundHex: "#1A1A1A",
            accentHex: "#6366F1",
            borderHex: "#C5CAE0",
            wallpaperNames: [
                "turquoise-lake-aerial-view",
                "lavender-bloom-macro-detail",
                "white-building-blue-sky",
                "pale-blue-pool-diagonal-shadow",
                "frosted-glass-blue-violet-light"
            ],
            isDark: false
        ),
        Theme(
            id: .midnight,
            displayName: "Midnight",
            mood: "Ink-blue darkness with a soft indigo glow",
            chromeHex: "#1C1E2A",
            foregroundHex: "#E2E4EA",
            accentHex: "#818CF8",
            borderHex: "#3A3D50",
            wallpaperNames: [
                "starry-night-mountain-silhouette",
                "city-grid-at-night-amber-lights",
                "volcanic-rock-blue-glow",
                "long-exposure-waves-dark-rocks",
                "ink-in-water-indigo-swirls"
            ],
            isDark: true
        ),
        Theme(
            id: .sandstone,
            displayName: "Sandstone",
            mood: "Sun-baked clay and natural linen",
            chromeHex: "#D4C4A8",
            foregroundHex: "#2C2416",
            accentHex: "#C2703E",
            borderHex: "#BFB093",
            wallpaperNames: [
                "sand-dunes-golden-hour",
                "terracotta-rooftops-warm-ochre",
                "raw-linen-fabric-soft-light",
                "desert-canyon-layered-sandstone",
                "ceramic-bowl-window-light"
            ],
            isDark: false
        ),
        Theme(
            id: .nordic,
            displayName: "Nordic",
            mood: "Scandinavian winter clarity, fjord-blue accents",
            chromeHex: "#C9D0DC",
            foregroundHex: "#1E2A33",
            accentHex: "#5B8FA8",
            borderHex: "#BCC4D1",
            wallpaperNames: [
                "fjord-overcast-light",
                "birch-forest-winter",
                "scandinavian-interior-pale-wood",
                "frozen-lake-ice-cracks",
                "coastal-rocks-lichen-calm-sea"
            ],
            isDark: false
        ),
        Theme(
            id: .rosewood,
            displayName: "Rosewood",
            mood: "Dusty rose with warm plum undertones",
            chromeHex: "#DCCDD2",
            foregroundHex: "#2D1F23",
            accentHex: "#A3586C",
            borderHex: "#C4B2B8",
            wallpaperNames: [
                "pampas-grass-pale-pink-wall",
                "pink-marble-veins-blush",
                "flat-lay-dried-flowers-linen",
                "cherry-blossoms-muted-sky",
                "rose-concrete-shadow-play"
            ],
            isDark: false
        ),
        Theme(
            id: .verdant,
            displayName: "Verdant",
            mood: "Botanical green, sunlit greenhouse",
            chromeHex: "#B4C4B0",
            foregroundHex: "#1A261A",
            accentHex: "#527C52",
            borderHex: "#A8B8A4",
            wallpaperNames: [
                "monstera-leaves-water-droplets",
                "misty-forest-path-soft-green",
                "terraced-rice-paddies-emerald",
                "moss-on-ancient-stone-rain",
                "greenhouse-climbing-plants"
            ],
            isDark: false
        ),
        Theme(
            id: .graphite,
            displayName: "Graphite",
            mood: "Neutral warm grays — invisible chrome",
            chromeHex: "#C8C8C8",
            foregroundHex: "#222222",
            accentHex: "#5A5A5A",
            borderHex: "#B5B5B5",
            wallpaperNames: [
                "brutalist-curves-concrete",
                "fog-over-mountain-ridge",
                "pencil-strokes-textured-paper",
                "pebble-beach-mist-gray-stones",
                "abstract-gray-geometric-shapes"
            ],
            isDark: false
        )
    ]

    static func theme(for id: ThemeID) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }
}
```

**Step 2: Add the file to the Xcode project**

Open `Browse.xcodeproj` in Xcode, right-click the `Browse` group, choose `Add Files to "Browse"…`, select `Browse/Theme/Theme.swift`, ensure the `Browse` target is checked, click Add. **Do not create a new group** — add to the existing `Browse` group so the file appears under a new `Theme` subgroup.

**Step 3: Build to verify it compiles**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -20`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Browse/Theme/Theme.swift Browse.xcodeproj
git commit -m "feat(theme): add Theme model and catalog of 7 themes"
```

---

## Task 2: Create `ThemeStore` with UserDefaults persistence

**Files:**
- Create: `Browse/Theme/ThemeStore.swift`

**Step 1: Create the file**

Create `Browse/Theme/ThemeStore.swift`:

```swift
import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class ThemeStore {

    static let shared = ThemeStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let themeID = "settings.themeID"
    }

    /// The currently selected theme identifier. Observers re-render when this changes.
    private(set) var currentThemeID: ThemeID

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.themeID),
           let id = ThemeID(rawValue: raw) {
            self.currentThemeID = id
        } else {
            self.currentThemeID = .default
        }
    }

    // MARK: - Public API

    var current: Theme {
        Theme.theme(for: currentThemeID)
    }

    func select(_ id: ThemeID) {
        guard id != currentThemeID else { return }
        currentThemeID = id
        defaults.set(id.rawValue, forKey: Keys.themeID)
    }

    // MARK: - Color convenience accessors

    var chromeColor: NSColor { current.chromeColor }
    var foregroundColor: NSColor { current.foregroundColor }
    var accentColor: NSColor { current.accentColor }
    var borderColor: NSColor { current.borderColor }
    var isDark: Bool { current.isDark }
}
```

**Step 2: Add to Xcode project**

Add `Browse/Theme/ThemeStore.swift` to the `Browse` target the same way as Task 1.

**Step 3: Build to verify**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Browse/Theme/ThemeStore.swift Browse.xcodeproj
git commit -m "feat(theme): add ThemeStore with UserDefaults persistence"
```

---

## Task 3: Make `Colors` and `SettingsColors` theme-aware

**Files:**
- Modify: `Browse/Shared/Constants.swift`

**Step 1: Read the current file**

Open `Browse/Shared/Constants.swift`. Replace the `Colors` enum (lines 5–23) and the `SettingsColors` enum (lines 68–83) with computed properties that read from `ThemeStore.shared`.

**Step 2: Replace `Colors` enum**

Replace:

```swift
enum Colors {
    // Foreground
    static let foregroundPrimary   = NSColor(hex: "#1A1A1A")
    static let foregroundSecondary = NSColor(hex: "#5A5E6B")
    static let foregroundMuted     = NSColor(hex: "#00000")
    static let foregroundInverse   = NSColor(hex: "#FFFFFF")

    // Surfaces
    static let surfacePrimary   = NSColor(hex: "#FFFFFF")
    static let surfaceSecondary = NSColor(hex: "#EAECF5")
    static let surfaceInverse   = NSColor(hex: "#0A0A0A")

    // UI
    static let accentPrimary = NSColor(hex: "#6366F1")
    static let borderLight   = NSColor(hex: "#C5CAE0")
    static let hoverBg       = NSColor(hex: "#D0D5EB")
    static let sidebarBg     = NSColor(hex: "#B8BFD9")
    static let chromeBg      = NSColor(hex: "#92b4f4")
}
```

With:

```swift
enum Colors {
    // MARK: - Theme-aware tokens (resolve through ThemeStore)
    @MainActor static var foregroundPrimary: NSColor   { ThemeStore.shared.foregroundColor }
    @MainActor static var foregroundSecondary: NSColor { ThemeStore.shared.foregroundColor.withAlphaComponent(0.7) }
    @MainActor static var foregroundMuted: NSColor     { ThemeStore.shared.foregroundColor.withAlphaComponent(0.55) }
    @MainActor static var accentPrimary: NSColor       { ThemeStore.shared.accentColor }
    @MainActor static var borderLight: NSColor         { ThemeStore.shared.borderColor }
    @MainActor static var hoverBg: NSColor             { ThemeStore.shared.accentColor.withAlphaComponent(0.12) }
    @MainActor static var sidebarBg: NSColor           { ThemeStore.shared.chromeColor }
    @MainActor static var chromeBg: NSColor            { ThemeStore.shared.chromeColor }

    // MARK: - Static (non-themed) tokens
    static let foregroundInverse = NSColor(hex: "#FFFFFF")
    static let surfacePrimary    = NSColor(hex: "#FFFFFF")
    static let surfaceSecondary  = NSColor(hex: "#F7F8FA")
    static let surfaceInverse    = NSColor(hex: "#0A0A0A")
}
```

**Step 3: Replace `SettingsColors` enum**

Replace:

```swift
enum SettingsColors {
    static let chrome = Color(hex: "#C4CBE3")
    static let windowBorder = Color(hex: "#9BA3C4")
    static let surface = Color.white
    static let borderLight = Color(hex: "#C5CAE0")
    static let accent = Color(hex: "#6366F1")
    static let fgPrimary = Color(hex: "#1A1A1A")
    static let fgSecondary = Color(hex: "#5A5E6B")
    static let hover = Color(hex: "#D0D5EB")
    static let danger = Color(hex: "#EF4444")
    static let allowGreen = Color(hex: "#22C55E")
    static let denyRed = Color(hex: "#EF4444")
    static let trafficRed = Color(hex: "#FF5F57")
    static let trafficYellow = Color(hex: "#FEBC2E")
    static let trafficGreen = Color(hex: "#28C840")
}
```

With:

```swift
enum SettingsColors {
    // MARK: - Theme-aware tokens
    @MainActor static var chrome: Color       { Color(nsColor: ThemeStore.shared.chromeColor) }
    @MainActor static var windowBorder: Color { Color(nsColor: ThemeStore.shared.borderColor) }
    @MainActor static var borderLight: Color  { Color(nsColor: ThemeStore.shared.borderColor) }
    @MainActor static var accent: Color       { Color(nsColor: ThemeStore.shared.accentColor) }
    @MainActor static var fgPrimary: Color    { Color(nsColor: ThemeStore.shared.foregroundColor) }
    @MainActor static var fgSecondary: Color  { Color(nsColor: ThemeStore.shared.foregroundColor).opacity(0.7) }
    @MainActor static var hover: Color        { Color(nsColor: ThemeStore.shared.accentColor).opacity(0.12) }

    // MARK: - Static (non-themed)
    static let surface       = Color.white
    static let danger        = Color(hex: "#EF4444")
    static let allowGreen    = Color(hex: "#22C55E")
    static let denyRed       = Color(hex: "#EF4444")
    static let trafficRed    = Color(hex: "#FF5F57")
    static let trafficYellow = Color(hex: "#FEBC2E")
    static let trafficGreen  = Color(hex: "#28C840")
}
```

**Step 4: Build and fix callers**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -40`

Expect some compile errors from callers that read `.surfaceSecondary`, `.trafficGreen`, etc. without `@MainActor` context. If errors appear:

- If error says "actor-isolated ... cannot be referenced from a nonisolated context": add `@MainActor` to the calling function/view-model, or call from an existing `@MainActor` context.
- Fix until `** BUILD SUCCEEDED **`.

**Step 5: Manual verification**

1. Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -5`
2. Launch the built app:
   ```bash
   open /Users/omarelsayed/Library/Developer/Xcode/DerivedData/Browse-*/Build/Products/Debug/Browse.app
   ```
3. Verify the app opens and looks visually identical to before (Periwinkle default). No crashes.

**Step 6: Commit**

```bash
git add Browse/Shared/Constants.swift
git commit -m "refactor(theme): make Colors and SettingsColors resolve through ThemeStore"
```

---

## Task 4: Add 35 wallpaper images to the app bundle

**Files:**
- Modify: `Browse.xcodeproj/project.pbxproj` (via Xcode UI)

**Step 1: In Xcode**

Open `Browse.xcodeproj`. In the project navigator:

1. Right-click the `Browse` group → `Add Files to "Browse"…`
2. Navigate to `/Users/omarelsayed/Desktop/MyAPPs/Browse/Browse/images/`
3. Select the entire `images` **folder** (not the individual files)
4. In the dialog:
   - ✅ **Copy items if needed:** uncheck (the folder is already in place)
   - **Added folders:** select **"Create folder references"** (blue folder, not groups). This preserves the flat folder at runtime as `Bundle.main.url(forResource: "name", withExtension: "jpg", subdirectory: "images")`.
   - ✅ **Add to targets:** Browse
5. Click **Add**.

**Step 2: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Verify images are bundled**

Run: `find /Users/omarelsayed/Library/Developer/Xcode/DerivedData/Browse-*/Build/Products/Debug/Browse.app -name "*.jpg" | head -5`

Expected: 5 lines of `.jpg` paths inside `Browse.app/Contents/Resources/images/`.

**Step 4: Commit**

```bash
git add Browse.xcodeproj
git commit -m "feat(theme): bundle 35 wallpaper images as folder reference"
```

---

## Task 5: Observe theme changes and trigger chrome re-render

**Files:**
- Modify: `Browse/Window/BrowserWindowController.swift`
- Modify: `Browse/Window/MainSplitViewController.swift` (add a `reapplyTheme()` method)

**Step 1: Inspect `MainSplitViewController` structure**

Run: `grep -n "backgroundColor\|layer" Browse/Window/MainSplitViewController.swift | head -20`

Identify which views set their own background color / layer. You need these to call `needsDisplay = true` when the theme flips. Typical views that draw the chrome: sidebar host view, toolbar host view, history panel host view, downloads panel host view.

**Step 2: Add `reapplyTheme()` to `MainSplitViewController`**

At the bottom of `MainSplitViewController` (before the closing brace), add:

```swift
    // MARK: - Theme re-render

    /// Walk all theme-sensitive subviews and force a redraw.
    /// Called by BrowserWindowController when ThemeStore.currentThemeID changes.
    func reapplyTheme() {
        // Force the entire view tree to redraw.
        view.needsDisplay = true
        view.layoutSubtreeIfNeeded()
        walkAndInvalidate(view)
    }

    private func walkAndInvalidate(_ v: NSView) {
        v.needsDisplay = true
        // Redraw layer-backed views
        if let layer = v.layer {
            layer.setNeedsDisplay()
            // Layer-backed views with a backgroundColor set from theme need re-setting
            v.needsLayout = true
        }
        for sub in v.subviews { walkAndInvalidate(sub) }
    }
```

**Step 3: Extend the observation task in `BrowserWindowController`**

In `Browse/Window/BrowserWindowController.swift`, find the `observationTask = Task { [weak self] in` block (around line 81). Add `var lastThemeID: ThemeID?` alongside the other `last…` variables, and inside the `while` loop add a check **at the top** of each iteration:

Replace (around line 83, the `var` declarations):

```swift
            var lastID: UUID?
            var lastURL: URL?
            var lastProgress: Double = 0
            var lastLoading: Bool = false
            var lastDownloadSignature: String = ""
```

With:

```swift
            var lastID: UUID?
            var lastURL: URL?
            var lastProgress: Double = 0
            var lastLoading: Bool = false
            var lastDownloadSignature: String = ""
            var lastThemeID: ThemeID? = ThemeStore.shared.currentThemeID
```

Then, immediately after the `while !Task.isCancelled {` line, add:

```swift
                // Theme change detection
                let currentThemeID = ThemeStore.shared.currentThemeID
                if currentThemeID != lastThemeID {
                    lastThemeID = currentThemeID
                    splitVC.reapplyTheme()
                    splitVC.addressBar.updateForTab(tabManager.selectedTab)
                }
```

**Step 4: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Manual verification (temporary debug call)**

Before committing, briefly test the re-render works: in `AppDelegate` or a menu item, temporarily call `ThemeStore.shared.select(.midnight)` and verify the chrome changes within ~100 ms. Revert the debug call.

Alternative — skip manual verification here; it'll be fully tested once the picker UI exists in Task 11.

**Step 6: Commit**

```bash
git add Browse/Window/BrowserWindowController.swift Browse/Window/MainSplitViewController.swift
git commit -m "feat(theme): observe ThemeStore changes and re-render chrome"
```

---

## Task 6: Create the `blur://newtab` and `blur-image://` URL scheme handler

**Files:**
- Create: `Browse/WebContent/BlurSchemeHandler.swift`
- Create: `Browse/Theme/NewTabPageHTMLBuilder.swift`

**Step 1: Create `NewTabPageHTMLBuilder.swift`**

```swift
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
            <div class="greeting">\(greeting)</div>
            <form class="search-wrap" onsubmit="return submitSearch(event)">
              <svg class="search-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
              <input id="q" class="search" type="text" placeholder="\(searchPlaceholder)" autocomplete="off" autofocus>
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
}
```

**Step 2: Create `BlurSchemeHandler.swift`**

```swift
import Foundation
import WebKit

/// Serves `blur://newtab` (themed HTML) and `blur-image://<name>.jpg` (bundled wallpaper).
@MainActor
final class BlurSchemeHandler: NSObject, WKURLSchemeHandler {

    nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        Task { @MainActor in
            await handle(urlSchemeTask)
        }
    }

    nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No long-running work to cancel.
    }

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
        let cleanName = filename
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        // Split into name + extension
        guard let dotRange = cleanName.range(of: ".", options: .backwards) else {
            fail(task, reason: "no extension in \(cleanName)")
            return
        }
        let name = String(cleanName[..<dotRange.lowerBound])
        let ext = String(cleanName[dotRange.upperBound...])

        guard let fileURL = Bundle.main.url(
            forResource: name,
            withExtension: ext,
            subdirectory: "images"
        ), let data = try? Data(contentsOf: fileURL) else {
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
```

**Step 3: Add both files to the Xcode project**

In Xcode, right-click `Browse/WebContent` group → add `BlurSchemeHandler.swift`. Right-click `Browse/Theme` group → add `NewTabPageHTMLBuilder.swift`. Both to target `Browse`.

**Step 4: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```bash
git add Browse/WebContent/BlurSchemeHandler.swift Browse/Theme/NewTabPageHTMLBuilder.swift Browse.xcodeproj
git commit -m "feat(theme): add blur:// scheme handler and new tab HTML builder"
```

---

## Task 7: Register `blur://` scheme in every tab's WKWebView + handle search submit

**Files:**
- Modify: `Browse/Tab/BrowserTab.swift`

**Step 1: Register the scheme handler**

In `Browse/Tab/BrowserTab.swift`, inside `makeFilterConfiguration()` (around line 124), **before** the `return config` statement at line 169, add:

```swift
        // Register blur:// and blur-image:// scheme handlers for the themed new tab page.
        let blurHandler = BlurSchemeHandler()
        config.setURLSchemeHandler(blurHandler, forURLScheme: "blur")
        config.setURLSchemeHandler(blurHandler, forURLScheme: "blur-image")

        // Apply the current theme's color scheme preference so websites that
        // support prefers-color-scheme react to dark themes.
        config.defaultWebpagePreferences.preferredContentMode = .desktop
```

**Step 2: Update the `preferredColorScheme` per tab**

At the bottom of `BrowserTab`'s init (right after `observeWebView(wv)` and before `if let url { wv.load… }`), add:

```swift
        // Sync the initial color scheme to the active theme
        Self.syncColorScheme(wv)
```

Then add a new static helper at the end of the class (before the closing brace on line 171):

```swift
    /// Apply the active theme's `isDark` flag to the web view's page preferences
    /// so websites can react via `prefers-color-scheme`.
    static func syncColorScheme(_ wv: WKWebView) {
        let isDark = ThemeStore.shared.isDark
        wv.underPageBackgroundColor = isDark ? NSColor.black : NSColor.white
        // Appearance affects system color scheme inside WKWebView
        wv.appearance = isDark
            ? NSAppearance(named: .darkAqua)
            : NSAppearance(named: .aqua)
    }
```

**Step 3: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```bash
git add Browse/Tab/BrowserTab.swift
git commit -m "feat(theme): register blur:// scheme and apply color scheme to tabs"
```

---

## Task 8: Make new tabs navigate to `blur://newtab`

**Files:**
- Modify: `Browse/Shared/Constants.swift`
- Modify: `Browse/Tab/TabManager.swift`

**Step 1: Add a new-tab URL constant**

In `Browse/Shared/Constants.swift`, find the `AppConstants` enum and add a new constant:

```swift
enum AppConstants {
    static let defaultSearchURL = "https://www.google.com/search?q="
    static let googleSuggestURL = "https://suggestqueries.google.com/complete/search?client=firefox&q="
    static let defaultHomeURL   = "https://www.google.com"
    static let newTabURL        = "blur://newtab"        // ← new line
    static let appName = "Blur-Browser"
}
```

**Step 2: Change `TabManager.init` and `addNewTab` to use the new-tab URL**

In `Browse/Tab/TabManager.swift`, line 32–34:

Replace:
```swift
    init() {
        addNewTab(url: URL(string: SettingsStore.shared.homepageURL))
    }
```

With:
```swift
    init() {
        addNewTab(url: URL(string: AppConstants.newTabURL))
    }
```

Then in `addNewTab(url:afterCurrent:)` at line 37, change the default:

Replace:
```swift
    @discardableResult
    func addNewTab(url: URL? = nil, afterCurrent: Bool = true) -> BrowserTab {
        let tab = BrowserTab(url: url)
```

With:
```swift
    @discardableResult
    func addNewTab(url: URL? = nil, afterCurrent: Bool = true) -> BrowserTab {
        let resolvedURL = url ?? URL(string: AppConstants.newTabURL)
        let tab = BrowserTab(url: resolvedURL)
```

**Step 3: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 4: Manual verification**

1. Launch the built app.
2. Press ⌘+T to open a new tab.
3. Expected: a new tab appears with a random wallpaper background + search field + time-based greeting ("Good afternoon" etc.).
4. Type a query + press Enter → nothing happens yet (Task 9 wires submit). That's expected at this step.

If the page is blank or shows the search field without a wallpaper, verify the images bundle loaded: `ls /Users/omarelsayed/Library/Developer/Xcode/DerivedData/Browse-*/Build/Products/Debug/Browse.app/Contents/Resources/images/*.jpg | head -3`

**Step 5: Commit**

```bash
git add Browse/Shared/Constants.swift Browse/Tab/TabManager.swift
git commit -m "feat(theme): route new tabs to blur://newtab themed page"
```

---

## Task 9: Wire the new-tab search field submit to navigate the active tab

**Files:**
- Modify: `Browse/Tab/BrowserTab.swift`
- Modify: `Browse/WebContent/WebViewController.swift` (or wherever the tab hosts the user content controller)

**Step 1: Inspect how user content messages are handled**

Run: `grep -rn "WKScriptMessageHandler\|messageHandlers\|addScriptMessageHandler" Browse/ | head -10`

Likely no existing usage. We'll add a lightweight handler on the shared config.

**Step 2: Add a script message handler to forward search submits**

In `Browse/Tab/BrowserTab.swift`, in `makeFilterConfiguration()`, add — **after** the scheme handler registration from Task 7:

```swift
        // Receive submit events from the blur://newtab search form
        let messageHandler = NewTabSubmitMessageHandler()
        config.userContentController.add(messageHandler, name: "newTabSubmit")
```

**Step 3: Create the message handler class**

At the bottom of `Browse/Tab/BrowserTab.swift` (after the `extension BrowserTab: Hashable`), add:

```swift
// MARK: - New Tab submit bridge

/// Receives `window.webkit.messageHandlers.newTabSubmit.postMessage(query)` calls
/// from the themed new-tab HTML and routes them through `TabManager.navigate(to:)`.
@MainActor
final class NewTabSubmitMessageHandler: NSObject, WKScriptMessageHandler {

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            guard let query = message.body as? String,
                  !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }

            // Find the window that owns this web view's tab and navigate.
            // Current design has one TabManager per window; reach it via the key window.
            guard let controller = NSApp.keyWindow?.windowController as? BrowserWindowController else { return }
            controller.tabManager.navigate(to: query)
        }
    }
}
```

**Step 4: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Manual verification**

1. Launch the built app.
2. Press ⌘+T to open a new tab.
3. Type `apple.com` + Enter → the tab navigates to apple.com.
4. Open another new tab, type `swift concurrency tutorial` + Enter → the tab runs a Google search.

**Step 6: Commit**

```bash
git add Browse/Tab/BrowserTab.swift
git commit -m "feat(theme): wire new-tab search submit via WKScriptMessageHandler"
```

---

## Task 10: Add "Appearance" tab to the Settings window

**Files:**
- Modify: `Browse/Settings/SettingsView.swift`
- Create: `Browse/Settings/AppearanceSettingsView.swift`

**Step 1: Add the case to `SettingsTab`**

In `Browse/Settings/SettingsView.swift`, line 3–9, replace:

```swift
enum SettingsTab: String, CaseIterable {
    case general = "General"
    case privacy = "Privacy"
    case permissions = "Permissions"
    case shortcuts = "Shortcuts"
    case about = "About"
}
```

With:

```swift
enum SettingsTab: String, CaseIterable {
    case general = "General"
    case appearance = "Appearance"
    case privacy = "Privacy"
    case permissions = "Permissions"
    case shortcuts = "Shortcuts"
    case about = "About"
}
```

Then in the `switch selectedTab` block (around line 109), add the new case **before** `.privacy`:

```swift
                case .general:
                    GeneralSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .privacy:
                    PrivacySettingsView()
```

**Step 2: Create `AppearanceSettingsView.swift`**

```swift
import SwiftUI

struct AppearanceSettingsView: View {
    @State private var themeStore = ThemeStore.shared

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme")
                    .font(.custom(Typography.fontFamily, size: 13))
                    .foregroundStyle(SettingsColors.fgPrimary)

                Text("Choose a theme. The selected theme colors the sidebar, toolbar, and all panels. Each theme comes with a curated set of new-tab wallpapers.")
                    .font(.custom(Typography.fontFamily, size: 11))
                    .foregroundStyle(SettingsColors.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Theme.all) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: theme.id == themeStore.currentThemeID
                        ) {
                            themeStore.select(theme.id)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: Theme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                info
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected
                            ? Color(nsColor: theme.accentColor)
                            : Color(hex: "#E5E7EB"),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: isSelected
                    ? Color(nsColor: theme.accentColor).opacity(0.2)
                    : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 2,
                x: 0, y: isSelected ? 4 : 1
            )
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            // Mini browser chrome strip
            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: theme.accentColor)).frame(width: 6, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(height: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color(nsColor: theme.borderColor), lineWidth: 0.5)
                    )
                Spacer()
                Text("Aa")
                    .font(.custom(Typography.fontFamily, size: 9).weight(.semibold))
                    .foregroundStyle(Color(nsColor: theme.foregroundColor))
            }
            .padding(.horizontal, 10)
            .frame(height: 68)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: theme.chromeColor))

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: theme.accentColor), .white)
                    .padding(6)
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10
            )
        )
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(theme.displayName)
                .font(.custom(Typography.fontFamily, size: 12).weight(.semibold))
                .foregroundStyle(SettingsColors.fgPrimary)
            Text(theme.mood)
                .font(.custom(Typography.fontFamily, size: 10))
                .foregroundStyle(SettingsColors.fgSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
```

**Step 3: Add to Xcode project**

Right-click `Browse/Settings` group → add `AppearanceSettingsView.swift` to target.

**Step 4: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 5: Manual verification**

1. Launch the app.
2. Open Settings (⌘+,) → click "Appearance" tab.
3. Expected: 7 theme cards in a 2-column grid. The current theme has an accent-colored ring + checkmark.
4. Click a different theme (e.g. Midnight) → the chrome of the main browser window changes within 100 ms. The Appearance tab's selection ring moves to Midnight.
5. Open a new tab → verify the wallpaper matches the new theme.
6. Quit + relaunch → verify Midnight persists as the active theme.

**Step 6: Commit**

```bash
git add Browse/Settings/SettingsView.swift Browse/Settings/AppearanceSettingsView.swift Browse.xcodeproj
git commit -m "feat(theme): add Appearance settings tab with theme picker grid"
```

---

## Task 11: Add the quick-switch palette button to the sidebar

**Files:**
- Create: `Browse/Settings/ThemePickerPopover.swift`
- Modify: `Browse/Sidebar/TabsSideBarView/SubViews/SidebarButtons.swift`

**Step 1: Create `ThemePickerPopover.swift`**

```swift
import SwiftUI
import AppKit

// MARK: - Popover view (SwiftUI content)

struct ThemePickerPopoverView: View {
    @State private var themeStore = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Theme")
                .font(.custom(Typography.fontFamily, size: 11).weight(.semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(Theme.all) { theme in
                    swatch(theme)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func swatch(_ theme: Theme) -> some View {
        let isSelected = theme.id == themeStore.currentThemeID
        return Button {
            themeStore.select(theme.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(nsColor: theme.chromeColor))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(nsColor: theme.borderColor), lineWidth: 1)
                    )

                // Accent dot
                Circle()
                    .fill(Color(nsColor: theme.accentColor))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle().strokeBorder(Color.white, lineWidth: 1.5)
                    )
                    .offset(x: 2, y: 2)

                if isSelected {
                    Circle()
                        .strokeBorder(Color(nsColor: theme.accentColor), lineWidth: 2)
                        .frame(width: 34, height: 34)
                        .offset(x: -3, y: -3)
                }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
    }
}

// MARK: - NSPopover host

@MainActor
final class ThemePickerPopoverController {

    static let shared = ThemePickerPopoverController()

    private let popover: NSPopover

    private init() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: ThemePickerPopoverView())
        popover.contentViewController = host
    }

    func show(relativeTo view: NSView) {
        if popover.isShown {
            popover.close()
            return
        }
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }
}
```

**Step 2: Add to Xcode project**

Add `Browse/Settings/ThemePickerPopover.swift` to target.

**Step 3: Add the palette button**

In `Browse/Sidebar/TabsSideBarView/SubViews/SidebarButtons.swift`, **before** the settings gear button (around line 62), insert:

```swift
            Button {
                if let window = NSApp.keyWindow,
                   let responder = window.firstResponder as? NSView {
                    ThemePickerPopoverController.shared.show(relativeTo: responder)
                } else if let window = NSApp.keyWindow,
                          let contentView = window.contentView {
                    ThemePickerPopoverController.shared.show(relativeTo: contentView)
                }
            } label: {
                Image(systemName: "paintpalette")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            }
            .buttonStyle(.plain)
            .help("Change Theme")
```

This is a rough anchor — the popover will show near the window. Fine-tune anchoring later if needed.

**Step 4: Improve anchor (optional polish)**

Swap the anchoring to use a `GeometryReader`-friendly wrapper. Skip for now; the above is good enough for v1.

**Step 5: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 6: Manual verification**

1. Launch the app.
2. In the sidebar footer, confirm a new 🎨 palette icon appears next to the gear.
3. Click it → a popover appears with 7 circular swatches, each showing its chrome color + an accent-color dot, with the active theme ringed.
4. Click a swatch → theme switches immediately, popover stays open.
5. Click outside the popover → dismisses.
6. Hover a swatch → tooltip shows the theme name.

**Step 7: Commit**

```bash
git add Browse/Settings/ThemePickerPopover.swift Browse/Sidebar/TabsSideBarView/SubViews/SidebarButtons.swift Browse.xcodeproj
git commit -m "feat(theme): add sidebar palette button and quick-switch popover"
```

---

## Task 12: Update color scheme when theme changes at runtime

**Files:**
- Modify: `Browse/Window/BrowserWindowController.swift`

**Step 1: Sync color scheme for existing tabs on theme change**

In `Browse/Window/BrowserWindowController.swift`, inside the theme-change branch added in Task 5, extend it to walk all tabs and sync their `appearance`:

Find:
```swift
                // Theme change detection
                let currentThemeID = ThemeStore.shared.currentThemeID
                if currentThemeID != lastThemeID {
                    lastThemeID = currentThemeID
                    splitVC.reapplyTheme()
                    splitVC.addressBar.updateForTab(tabManager.selectedTab)
                }
```

Replace with:
```swift
                // Theme change detection
                let currentThemeID = ThemeStore.shared.currentThemeID
                if currentThemeID != lastThemeID {
                    lastThemeID = currentThemeID
                    splitVC.reapplyTheme()
                    splitVC.addressBar.updateForTab(tabManager.selectedTab)
                    // Propagate the new color scheme (light/dark) to all live tabs.
                    for tab in tabManager.tabs {
                        BrowserTab.syncColorScheme(tab.webView)
                        // Force the new tab page to regenerate with the new theme's wallpaper
                        if tab.url?.absoluteString == AppConstants.newTabURL {
                            tab.webView.reload()
                        }
                    }
                }
```

**Step 2: Build**

Run: `xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`

**Step 3: Manual verification**

1. Launch the app, open a new tab (shows Periwinkle wallpaper).
2. Open a site that supports `prefers-color-scheme`: navigate to `https://github.com`.
3. Open Settings → Appearance → select **Midnight**. Verify:
   - Chrome flips to dark navy.
   - GitHub tab re-renders in dark mode.
   - New tab page (if visible in another tab) reloads with a Midnight wallpaper.
4. Select **Sandstone**. Verify GitHub returns to light mode and chrome is tan.

**Step 4: Commit**

```bash
git add Browse/Window/BrowserWindowController.swift
git commit -m "feat(theme): propagate color scheme and reload new-tab pages on theme change"
```

---

## Task 13: Polish — verify every chrome-colored view updates

**Files:**
- Modify (possibly): any view controller whose background is set once at init.

**Step 1: Systematic QA**

Run the app and switch through all 7 themes. For each theme, verify these surfaces match the chrome color:

- [ ] Sidebar background
- [ ] Toolbar / address bar background
- [ ] Title bar (traffic light area — should share chrome color for full-bleed effect)
- [ ] History panel (toggle with its shortcut / sidebar button)
- [ ] Downloads panel (trigger a download and open the panel)
- [ ] Authentication dialog (trigger via a site like `https://httpbin.org/basic-auth/user/pass`)
- [ ] Download confirmation sheet

If any surface sticks to the old color, find where it sets `backgroundColor` / layer background and fix it to read `Colors.chromeBg` on each layout pass:

- Replace one-time init-time assignments like `view.layer?.backgroundColor = Colors.chromeBg.cgColor` with overrides of `viewDidLayout` / `layout()` that re-read the value.

**Step 2: Fix any laggy surface**

For each sticky surface found in Step 1:
1. Locate the one-time assignment.
2. Move it into a method called from `viewDidLayout()` or override `updateLayer()`:
   ```swift
   override func updateLayer() {
       super.updateLayer()
       layer?.backgroundColor = Colors.chromeBg.cgColor
   }
   ```
3. Ensure `wantsLayer = true` is set on the view.

**Step 3: Build + verify**

After each fix, rebuild and re-switch themes. Mark the corresponding item in the QA checklist.

**Step 4: Commit**

```bash
git add -A
git commit -m "fix(theme): ensure all chrome surfaces re-render on theme change"
```

---

## Task 14: Final end-to-end QA + commit design & plan docs

**Step 1: Full QA script**

Walk through each scenario and mark pass/fail:

1. **Launch with no stored theme** → default is Periwinkle, chrome is periwinkle blue.
2. **Open Settings → Appearance** → grid of 7 cards visible, Periwinkle is ringed.
3. **Click each of the 7 themes** → chrome, accent, borders, panel backgrounds all update within 100 ms.
4. **Sidebar palette button** → popover opens, 7 swatches, active ringed, click switches, clicking outside dismisses.
5. **Open new tab (⌘+T)** → random wallpaper from active theme, search field auto-focused, time-based greeting shown.
6. **Type `apple.com` + Enter on new-tab page** → navigates to apple.com.
7. **Type `cute cats` + Enter on new-tab page** → runs search on configured search engine.
8. **Switch to Midnight + navigate to `github.com`** → GitHub renders dark.
9. **Quit + relaunch** → previous theme persists.
10. **Open a download confirmation** → panel uses chrome color.
11. **Open history panel** → uses chrome color.
12. **Open authentication dialog** (via a site requiring HTTP Basic auth) → uses chrome color.

**Step 2: Commit design doc**

```bash
git add docs/plans/2026-04-21-theme-picker-design.md docs/plans/2026-04-21-theme-picker.md
git commit -m "docs(theme): add design doc and implementation plan"
```

**Step 3: Optional polish**

Discuss with the user whether to:
- Animate theme transitions (CATransaction cross-fade).
- Add keyboard shortcut for the quick-switch popover.
- Allow right-click on a theme card to preview without applying.

These are not part of v1.

---

## Done

Plan complete and saved to `docs/plans/2026-04-21-theme-picker.md`. Two execution options:

**1. Subagent-Driven (this session)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Recommended since the tasks have clear boundaries and you can watch each one land.

**2. Parallel Session (separate)** — Open a new session with `executing-plans`, batch execution with checkpoints.

Which approach do you want?
