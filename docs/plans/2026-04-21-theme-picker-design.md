# Theme Picker — Design

**Date:** 2026-04-21
**Status:** Approved, ready for implementation

## Overview

Add a user-selectable theme system to Blur-Browser. Each theme defines:
- A unified **chrome color** applied to sidebar, toolbar, address bar, and all panels (history, downloads, auth dialogs, download-request sheets).
- A **text & icon color** for all foreground elements displayed on the chrome.
- An **accent color** for the active tab indicator, selected states, and primary actions.
- A **border color** for subtle dividers and strokes.
- A **set of 5 curated wallpaper images** displayed as a random full-bleed background on the new tab page instead of navigating to `google.com`.

The URL bar stays white (`#FFFFFF`) across every theme. Sidebar and chrome always share one color — no divider between them.

## The Theme Catalog

Seven themes, organized around **Places & Moods**. Each name evokes a sense of place; colors and wallpapers tell one cohesive story.

| # | Name | Chrome | Text/Icon | Accent | Border | Scheme |
|---|---|---|---|---|---|---|
| 1 | **Periwinkle** *(default)* | `#92B4F4` | `#1A1A1A` | `#6366F1` | `#C5CAE0` | light |
| 2 | **Midnight** | `#1C1E2A` | `#E2E4EA` | `#818CF8` | `#3A3D50` | dark |
| 3 | **Sandstone** | `#D4C4A8` | `#2C2416` | `#C2703E` | `#BFB093` | light |
| 4 | **Nordic** | `#C9D0DC` | `#1E2A33` | `#5B8FA8` | `#BCC4D1` | light |
| 5 | **Rosewood** | `#DCCDD2` | `#2D1F23` | `#A3586C` | `#C4B2B8` | light |
| 6 | **Verdant** | `#B4C4B0` | `#1A261A` | `#527C52` | `#A8B8A4` | light |
| 7 | **Graphite** | `#C8C8C8` | `#222222` | `#5A5A5A` | `#B5B5B5` | light |

The **Periwinkle** theme replicates the current app state (sidebar collapses to chrome color). Dark themes set `prefers-color-scheme: dark` via `WKWebView` configuration so websites that support dark mode adapt automatically.

## Wallpapers

35 bundled images (5 per theme), already present at `Browse/images/*.jpg` — filenames slugified from each wallpaper description. These need to be added to `Assets.xcassets` (or bundled as a folder reference) so they're available at runtime.

### Mapping (theme → wallpaper filenames)

**Periwinkle**: `turquoise-lake-aerial-view.jpg`, `lavender-bloom-macro-detail.jpg`, `white-building-blue-sky.jpg`, `pale-blue-pool-diagonal-shadow.jpg`, `frosted-glass-blue-violet-light.jpg`

**Midnight**: `starry-night-mountain-silhouette.jpg`, `city-grid-at-night-amber-lights.jpg`, `volcanic-rock-blue-glow.jpg`, `long-exposure-waves-dark-rocks.jpg`, `ink-in-water-indigo-swirls.jpg`

**Sandstone**: `sand-dunes-golden-hour.jpg`, `terracotta-rooftops-warm-ochre.jpg`, `raw-linen-fabric-soft-light.jpg`, `desert-canyon-layered-sandstone.jpg`, `ceramic-bowl-window-light.jpg`

**Nordic**: `fjord-overcast-light.jpg`, `birch-forest-winter.jpg`, `scandinavian-interior-pale-wood.jpg`, `frozen-lake-ice-cracks.jpg`, `coastal-rocks-lichen-calm-sea.jpg`

**Rosewood**: `pampas-grass-pale-pink-wall.jpg`, `pink-marble-veins-blush.jpg`, `flat-lay-dried-flowers-linen.jpg`, `cherry-blossoms-muted-sky.jpg`, `rose-concrete-shadow-play.jpg`

**Verdant**: `monstera-leaves-water-droplets.jpg`, `misty-forest-path-soft-green.jpg`, `terraced-rice-paddies-emerald.jpg`, `moss-on-ancient-stone-rain.jpg`, `greenhouse-climbing-plants.jpg`

**Graphite**: `brutalist-curves-concrete.jpg`, `fog-over-mountain-ridge.jpg`, `pencil-strokes-textured-paper.jpg`, `pebble-beach-mist-gray-stones.jpg`, `abstract-gray-geometric-shapes.jpg`

## Architecture

### Data model

```swift
enum ThemeID: String, CaseIterable, Sendable {
    case periwinkle, midnight, sandstone, nordic, rosewood, verdant, graphite
}

struct Theme: Sendable {
    let id: ThemeID
    let displayName: String
    let mood: String           // short description
    let chromeHex: String
    let foregroundHex: String
    let accentHex: String
    let borderHex: String
    let wallpaperNames: [String]   // matches filenames in Assets/images
    let isDark: Bool               // drives prefers-color-scheme
}
```

A single `Theme.all` static array holds all 7 themes. `Theme.default == .periwinkle`.

### State management

- **`ThemeStore`** — new `@Observable @MainActor` singleton (like `SettingsStore`). Holds `currentThemeID`, persisted to `UserDefaults` under key `settings.themeID`. Exposes:
  - `var current: Theme { get }` — current theme resolved from ID
  - `func select(_ id: ThemeID)` — mutates and persists
  - `var chromeColor: NSColor`, `var foregroundColor: NSColor`, `var accentColor: NSColor`, `var borderColor: NSColor` — computed helpers

- **`Colors` enum in `Constants.swift`** — becomes a thin wrapper that reads from `ThemeStore.shared.current` instead of returning static hex values. **Existing static tokens that are theme-aware are replaced with computed properties**. Non-themed tokens (e.g. `foregroundInverse`, `trafficRed/Yellow/Green`, `allowGreen`, `denyRed`) stay static.

- **`SettingsColors` enum (SwiftUI)** — same treatment. Computed properties that route through `ThemeStore`.

### Observation & re-render

All AppKit views read `Colors.sidebarBg` / `Colors.chromeBg` / etc. on every `viewDidLayout` or `updateLayer`. When the theme changes:

1. `ThemeStore.select()` sets `currentThemeID` — `@Observable` fires.
2. `BrowserWindowController`'s existing observation `Task` (already polling `tabManager.selectedTabID` every 50ms) gains a second polling branch that watches `themeStore.currentThemeID`. On change:
   - Calls `applyThemeToAllViews()` — walks the view hierarchy and calls `needsDisplay = true` on every view that reads theme colors, plus forces `MainSplitViewController.layoutSubviews()`.
   - Rebuilds the `WKWebView` configuration preference for `prefers-color-scheme` on the active web view (new tabs pick up the new setting automatically).

SwiftUI views re-render automatically because `ThemeStore` is `@Observable` and consuming views hold `@State private var themeStore = ThemeStore.shared`.

### New Tab page

Currently, `AppConstants.defaultHomeURL = "https://www.google.com"`. New behavior:

- A new internal URL scheme: `blur://newtab` (served via `WKURLSchemeHandler`).
- When `TabManager.newTab()` is called without a URL, it navigates to `blur://newtab` instead of `defaultHomeURL`.
- The scheme handler returns an HTML page with:
  - Full-bleed `<img>` background (random wallpaper from the current theme)
  - Centered search field overlay with backdrop-filter blur (matches existing `QuickSearchView` styling)
  - On submit: parent AppKit code catches a JS message and routes to either the search engine or the typed URL (reuses `QuickSearchViewModel` routing logic).
- A new SwiftUI component `NewTabPageHTMLBuilder` generates the HTML/CSS with interpolated colors and the wallpaper filename. Images are loaded as `blur-image://<filename>` (a second scheme handler that serves bytes from `Bundle.main`).

### Theme picker UI — two entry points

**(1) Settings → Appearance tab**
- New `AppearanceSettingsView` SwiftUI view added to the Settings window.
- 7 theme cards in a 2-column grid. Each card:
  - 200×120 mini-preview (chrome color + accent dot + "Aa" text sample)
  - Theme name + mood tagline
  - Selected card has an accent-colored ring + checkmark
- Click a card → `themeStore.select(.xxx)` → entire app re-skins immediately.

**(2) Sidebar palette icon**
- New icon button in the sidebar footer next to the existing settings gear.
- SF Symbol: `paintpalette`.
- Click opens an `NSPopover` anchored to the button, containing:
  - Compact grid of 7 color swatches (28pt circles) in one row
  - Each swatch fills with the theme's chrome color; the accent color shows as a small dot in the corner
  - Active theme has an outer ring
  - Hover shows the theme name as a tooltip
- Click a swatch → immediate theme switch + popover dismisses.

## File Changes

### New files
- `Browse/Theme/Theme.swift` — `ThemeID` enum, `Theme` struct, `Theme.all` catalog.
- `Browse/Theme/ThemeStore.swift` — `@Observable` singleton, UserDefaults persistence.
- `Browse/Theme/NewTabPageHTMLBuilder.swift` — HTML/CSS generator for `blur://newtab`.
- `Browse/WebContent/NewTabSchemeHandler.swift` — `WKURLSchemeHandler` for `blur://newtab` and `blur-image://<filename>`.
- `Browse/Settings/AppearanceSettingsView.swift` — SwiftUI grid of theme cards.
- `Browse/Settings/ThemePickerPopover.swift` — `NSPopover` host for the sidebar palette swatches.
- `Browse/Sidebar/TabsSideBarView/SubViews/ThemePaletteButton.swift` — the sidebar icon button.

### Modified files
- `Browse/Shared/Constants.swift` — convert `Colors` / `SettingsColors` theme-aware tokens to computed properties.
- `Browse/App/AppConstants` — replace `defaultHomeURL` hard-coded Google with `"blur://newtab"` (or add a new `newTabURL` constant).
- `Browse/Tab/TabManager.swift` — new-tab path uses `blur://newtab`.
- `Browse/WebContent/WebViewConfiguration.swift` — register the two scheme handlers; read `ThemeStore.shared.current.isDark` to set `webpagePreferences.preferredColorScheme` accordingly.
- `Browse/Window/BrowserWindowController.swift` — extend observation `Task` to watch `themeStore.currentThemeID` and trigger re-layout.
- `Browse/Window/MainSplitViewController.swift` — redraw background on theme change.
- `Browse/Toolbar/AddressBarViewController.swift` — redraw background.
- `Browse/Sidebar/SidebarViewController.swift` — redraw background.
- `Browse/History/HistoryPanelView.swift`, `Browse/Downloads/DownloadsPanelView.swift`, `Browse/WebContent/AuthenticationDialogView.swift`, `Browse/WebContent/DownloadConfirmationView.swift` — pick up new computed `Colors.*`.
- `Browse/Settings/SettingsWindowController.swift` — add "Appearance" tab.
- `Browse/Sidebar/TabsSideBarView/SubViews/SidebarButtons.swift` — add palette button next to settings gear.
- `Browse/Resources/Assets.xcassets` — add 35 images from `Browse/images/` as an Image Set group (or change the build phase to copy `Browse/images/` as a bundle resource folder reference).

## Error Handling

- **Missing wallpaper** — if a wallpaper filename can't be loaded from the bundle, the new-tab page falls back to a solid chrome-color background.
- **Unknown `themeID` in UserDefaults** (e.g. from a future build downgrade) — `ThemeStore` returns `.periwinkle` default and overwrites the invalid stored value.
- **Scheme handler failures** — `blur://newtab` returns a minimal HTML with just the chrome color and search field if the theme resolution fails.

## Testing

Since the project has no existing test target, manual QA only:
1. Launch → verify default is Periwinkle (current appearance).
2. Open Settings → Appearance → click each theme → verify chrome, text, accent, and border all update across: sidebar, address bar, history panel, downloads panel, auth dialog.
3. Click sidebar palette icon → popover shows 7 swatches → click each → immediate switch.
4. Open new tab → verify random wallpaper shows + search field works.
5. Quit + relaunch → verify selected theme persists.
6. Switch to Midnight → open a site that supports dark mode (e.g. github.com) → verify it renders dark.
7. Switch back to a light theme → verify the site re-renders light.

## Out of Scope (explicitly)

- Custom user-created themes.
- Theme scheduling (auto-switch at sunset, etc.).
- Per-site theme overrides.
- Animation of the theme transition (simple hard swap is fine).
- Migration of the `chromeBg` / `sidebarBg` color distinction in `Constants.swift` — they become aliases for the same `chrome` color.
