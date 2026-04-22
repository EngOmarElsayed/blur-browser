# AGENTS.md — Blur-Browser

> Read this **before touching code**. It captures architecture decisions, hard rules,
> and the known-gotcha list that keeps this app from breaking when you make changes.

---

## 1. What this is

**Blur-Browser** — a native macOS browser. SwiftUI for leaf views, AppKit for
everything structural (window chrome, sidebar, toolbar, `WKWebView` hosting,
overlays). Built for macOS 14+, Swift 5.10+.

- Xcode project: `Blur-Browser.xcodeproj`
- Scheme: `Blur-Browser`
- Bundle ID: `com.Blur-Browser.app`
- Single SPM dependency: a private `AsyncImage` library (github.com/EngOmarElsayed/AsyncImage) — though the source is **also vendored** in `Browse/AsyncImage/` for favicon rendering. Do not confuse the two.

### Build & run

```bash
xcodebuild -project Blur-Browser.xcodeproj -scheme Blur-Browser -configuration Debug build
```

The project uses Xcode's "Synchronized Folder" system — Swift files added to
`Browse/` are auto-included in the target (see `fileSystemSynchronizedGroups`
in `project.pbxproj`). **You do NOT need to add new files to the Xcode project
manually.** Just `Write` the file under `Browse/…`.

Exceptions are listed in `PBXFileSystemSynchronizedBuildFileExceptionSet`
(currently: `Assets.xcassets`, `Resources/Info.plist`).

---

## 2. Hard architectural rules

Violating any of these will silently break things or crash.

### AppKit hosts SwiftUI — never the other way around

- The window's content view controller is an AppKit `NSViewController`
  (`MainSplitViewController`)
- SwiftUI views are embedded as subviews via `NSHostingController`
- Manual frame-based layout for the split view — **no `NSSplitViewController`**
  (it causes infinite layout passes with `NSHostingController`)
- **No `NSToolbar` with custom view items** — same layout-cycle issue
- **Never set `NSHostingView` directly as `self.view`** on a controller —
  always wrap in a plain `NSView` container

### State management

- `@Observable` + `@MainActor` for every state class. **No `ObservableObject` / `@StateObject`.**
- `TabManager` is the single source of truth for tab state. All mutations go
  through its methods. Do not manipulate `tabs` array from anywhere else.
- Web state lives on `BrowserTab` — one `WKWebView` per tab, stored at
  `tab.webView`. Only the selected tab's web view is in the view hierarchy.

### Keyboard shortcuts

- All shortcuts are declared in `Browse/App/AppMenuBuilder.swift`
- **Every menu item targeting `AppDelegate` must have `target = delegate` set
  explicitly**. Otherwise shortcuts fail when `WKWebView` is first responder
  (the responder chain doesn't reach `AppDelegate` because web views consume
  events).
- For shortcuts that must work even when an in-process web window has focus
  (e.g., ⌘⌥C for Web Inspector), override `NSApplication.sendEvent(_:)` —
  see `Browse/App/main.swift` (`BrowserApplication`).

### Layout cycle prevention

The combo `fullSizeContentView` + `NSToolbar` + `NSSplitViewController` +
`NSHostingController` causes infinite layout passes on macOS. This project
avoids it by:
- Using a plain `NSViewController` (`MainSplitViewController`) with manual
  `frame` layout in `layoutSubviews()`
- No `NSToolbar` — the address bar is a regular view embedded in the
  content area
- `BrowserWindow` uses `.titled + .closable + .miniaturizable + .resizable
  + .fullSizeContentView` but **no** `.unifiedTitleAndToolbar`

### No 3rd party dependencies

Beyond the one vendored `AsyncImage`, do not add SPM/Cocoapods/Carthage
packages. Everything else is Foundation/AppKit/SwiftUI/WebKit/SwiftData.

---

## 3. Folder map

```
Browse/
├── App/
│   ├── main.swift                       # NSApplication subclass that intercepts ⌘⌥C
│   ├── AppDelegate.swift                # App lifecycle + forwards all actions to BrowserWindowController
│   └── AppMenuBuilder.swift             # Full menu bar with ALL keyboard shortcuts
│
├── Window/
│   ├── BrowserWindow.swift              # NSWindow subclass — also swallows unhandled keyDown to prevent beep
│   ├── BrowserWindowController.swift    # Owns TabManager, HistoryStore, DownloadStore, DownloadManager
│   └── MainSplitViewController.swift    # ROOT view controller — sidebar + toolbar + web view + overlays
│
├── Sidebar/
│   ├── SidebarViewController.swift      # AppKit host for the SwiftUI SidebarView
│   └── TabsSideBarView/
│       ├── SidebarView.swift            # SwiftUI root — holds SidebarState, Tabs vs Downloads
│       └── SubViews/
│           ├── SidebarContentView.swift  # Switches between Tabs list & Downloads list
│           ├── SidebarButtons.swift      # Bottom action row (Home / Downloads / History / Settings)
│           ├── PinnedTabsGrid.swift      # Pinned tabs section (top)
│           ├── PinnedTabItemView.swift   # Single pinned tab
│           ├── UnpinnedTabsList.swift    # Regular tab list
│           └── TabItemView.swift         # Single unpinned tab
│
├── Tab/
│   ├── BrowserTab.swift                 # @Observable — id, url, title, webView, isPinned, readerArticle, browsingError, etc.
│   ├── TabManager.swift                 # @Observable — source of truth. add/close/pin/unpin/move/navigate
│   ├── TabSessionStore.swift            # JSON persistence (session.json) — UNPINNED tabs only
│   ├── PinnedTabEntry.swift             # SwiftData @Model for pinned tabs
│   ├── PinnedTabStore.swift             # SwiftData store (PinnedTabs.store)
│   └── FaviconView.swift                # Shared favicon renderer
│
├── Toolbar/
│   └── AddressBarViewController.swift   # Back/forward/URL/reload/share/more/reader-pill
│
├── WebContent/
│   ├── WebViewController.swift          # Hosts WKWebView, find bar, overlays (error, reader, auth, download confirm)
│   ├── WebViewCoordinator.swift         # WKNavigationDelegate + WKUIDelegate — navigation, downloads, auth
│   ├── ContentFilterService.swift       # (NSFW content filter integration)
│   ├── PermissionBannerView.swift       # Camera/mic/location permission prompt
│   ├── AuthenticationDialogView.swift   # HTTP Basic Auth custom dialog
│   ├── DownloadConfirmationView.swift   # Allow/Deny modal before any download
│   ├── ErrorMessages.swift              # BrowsingError + funny error copy
│   ├── ErrorPageView.swift              # SwiftUI in-app error page (DNS/timeout/SSL/etc.)
│   ├── ReaderModeService.swift          # Readability.js integration + theme/font enums + HTML renderer
│   ├── ReaderModeView.swift             # Reader panel (AppKit) — theme/font picker popover
│   └── GaussianBlurView.swift           # Live blur via private CAFilter API
│
├── Downloads/
│   ├── DownloadItem.swift               # SwiftData @Model — fileName, localURL, totalBytes, status, resumeData
│   ├── DownloadStore.swift              # SwiftData store (Downloads.store) + CRUD
│   ├── DownloadManager.swift            # WKDownloadDelegate — beginDownload/cancel/pause/resume
│   ├── DownloadsToastView.swift         # SwiftUI floating toast (bottom-right of content area)
│   └── DownloadsPanelView.swift         # SwiftUI sidebar downloads list (replaces Tabs list in-place)
│
├── History/
│   ├── HistoryEntry.swift               # SwiftData @Model (default.store)
│   ├── HistoryStore.swift               # SwiftData store
│   ├── HistoryPanelView.swift           # SwiftUI right-side panel
│   ├── HistorySearchView.swift          # Search field
│   └── HistorySidebarView.swift         # (history-mode sidebar variant)
│
├── Search/
│   ├── QuickSearchPanel.swift           # ⌘K overlay with blocking dim view
│   ├── QuickSearchView.swift            # SwiftUI search UI (fixed 300pt)
│   ├── QuickSearchViewModel.swift       # @Observable — text, results, Google suggestions API
│   ├── FindInPageBar.swift              # ⌘F in-page search bar
│   └── FindInPageController.swift       # Drives WKWebView.find() API
│
├── Settings/
│   ├── SettingsWindowController.swift   # Custom chrome settings window (800×450, non-resizable)
│   ├── SettingsView.swift               # Main container — 5 custom pill-style tabs
│   ├── SettingsStore.swift              # @Observable UserDefaults-backed: homepage, search engine, restore-tabs
│   ├── GeneralSettingsView.swift        # Default browser + homepage + search engine + restore toggle
│   ├── PrivacySettingsView.swift        # Cookies table + clear browsing history/data
│   ├── SitePermissionsSettingsView.swift # Per-site camera/mic/location
│   ├── SitePermissionStore.swift        # JSON-in-UserDefaults persistence
│   ├── ShortcutsSettingsView.swift      # Read-only shortcuts table
│   └── AboutSettingsView.swift          # App icon + version + links
│
├── Shared/
│   ├── Constants.swift                  # Colors, Layout, Typography, AppConstants, NSColor/Color hex init
│   ├── KeyboardShortcuts.swift          # (legacy struct — menu-based shortcuts are canonical)
│   ├── ShortcutsCatalog.swift           # Canonical shortcuts data (feeds the cheat-sheet)
│   └── ShortcutsOverlayView.swift       # ⌘/ cheat sheet SwiftUI overlay
│
├── JS/
│   ├── content-filter.js                # NSFW/image filter runtime
│   ├── image-scanner.js                 # Catalog images for filtering
│   ├── video-scanner.js                 # Catalog videos
│   ├── Readability.js                   # Mozilla Readability (reader mode)
│   └── Readability-readerable.js        # Heuristic: "is this article-like?"
│
├── AsyncImage/                          # Vendored favicon image loader
├── Assets.xcassets/                     # App icon, Blur-icon
├── Blur-icon.icon/
├── NSFWClassifier.mlpackage/            # Core ML model used by ContentFilterService
└── Resources/
    ├── Info.plist                       # URL schemes (http, https), CFBundleDocumentTypes for default-browser
    └── Browse.entitlements              # Sandbox + hardened runtime + camera/mic/location
```

---

## 4. Data persistence — what lives where

| Data | Storage | File / Key |
|------|---------|-----------|
| Tab sessions (unpinned) | JSON | `~/Library/Application Support/Blur-Browser/session.json` |
| Pinned tabs | SwiftData | `~/Library/Application Support/Blur-Browser/PinnedTabs.store` |
| History | SwiftData (`default.store`) | same dir |
| Downloads (metadata) | SwiftData | `~/Library/Application Support/Blur-Browser/Downloads.store` |
| Settings (homepage, search engine, restore-tabs) | UserDefaults | `settings.homepageURL`, `settings.searchEngine`, `settings.restoreTabsOnLaunch` |
| Site permissions | UserDefaults (JSON-encoded) | `sitePermissions` |
| Reader theme / font | UserDefaults | `readerMode.theme`, `readerMode.font` |
| Cookies (incl. session cookies) | UserDefaults | `persistedCookies` |

### Gotcha: SwiftData file separation

Each `DownloadStore` / `PinnedTabStore` uses its **own** `ModelConfiguration`
with its **own** store URL. Do not merge schemas with `HistoryStore`'s
`default.store`. Early attempts at sharing failed because the first store
created the SQLite tables and later stores with different schemas couldn't
find their tables (`no such table: ZPINNEDTABENTRY` errors).

Example from `DownloadStore.swift`:
```swift
let config = ModelConfiguration("Downloads", url: storeURL)  // dedicated file
```

### Cookie persistence

Cookies are persisted entirely by `WKWebsiteDataStore.default()`, which stores
them encrypted in the app's sandbox container. We do NOT manually archive them
to UserDefaults — an earlier implementation did, but it wrote every cookie
(including `HttpOnly` / `Secure` session tokens) as plain JSON, creating a
credential-theft risk. The one-time cleanup in `AppDelegate.applicationDidFinish
Launching` removes the stale `persistedCookies` blob from older installs.

Trade-off: session cookies (no `expires` / no `max-age`) are dropped by WebKit
on quit — this matches the website's own intent. Some sites (e.g., Bitrise)
also store auth tokens in `localStorage`, which WebKit's default data store
*does* persist, so most logins survive relaunches anyway.

---

## 5. Observation pattern (no Combine)

This app uses a **polling-based observation loop** instead of Combine or
notifications. See `BrowserWindowController.setup()`:

```swift
observationTask = Task { [weak self] in
    while !Task.isCancelled {
        // Compare current state against last state, fire updates
        try? await Task.sleep(for: .milliseconds(50))
    }
}
```

It polls `tabManager.selectedTabID`, current tab URL, progress, loading state,
and the download signature every 50 ms. When anything changes, it triggers
the corresponding UI update (address bar, web view, reader mode sync,
downloads toast).

**Why polling?** `@Observable` doesn't expose a public "changed" signal
usable from AppKit. Notifications work but are brittle. The 50 ms loop is
cheap and reliably drives AppKit updates.

If you're adding a new piece of state that AppKit needs to react to, follow
this same pattern — add a `lastX` var and compare inside the loop.

---

## 6. Keyboard shortcuts — canonical list

All shortcuts are declared in `AppMenuBuilder.swift`. Keep `ShortcutsCatalog.swift`
and `ShortcutsSettingsView.swift` in sync when adding/removing.

| Shortcut | Action |
|---|---|
| ⌘T | New Tab |
| ⌘K | Quick Search |
| ⌘N | New Window |
| ⌘L | Open Location (focus address bar) |
| ⌘W | Close Tab |
| ⌘F | Find in Page |
| ⌘G | Find Next |
| ⇧⌘G | Find Previous |
| ⇧⌘C | Copy URL |
| ⌘\ | Toggle Sidebar |
| ⇧⌘\ | Toggle Sidebar (fallback when ⌘\ conflicts with a web app) |
| ⇧⌘F | Zen Mode (hides address bar + sidebar, reveals on top-hover) |
| ⇧⌘A | Toggle Address Bar only |
| ⌘R | Reload |
| ⇧⌘R | Hard Reload |
| ⌥⌘C | Web Inspector (intercepted via `BrowserApplication.sendEvent`) |
| ⇧⌘E | Easy Read (reader mode) |
| ⌥⌘L | Toggle Downloads list in sidebar |
| ⌘Y | Show History panel |
| ⌘[ | Back |
| ⌘] | Forward |
| ⇧⌘] | Next Tab |
| ⇧⌘[ | Previous Tab |
| ⌘1 – ⌘9 | Select Tab N |
| ⌘, | Settings |
| ⌘/ | Keyboard Shortcuts cheat sheet |

### Where each shortcut is wired

1. `AppMenuBuilder.swift` — adds menu item with key/modifiers
2. `AppDelegate.swift` — `@objc func` that looks up `BrowserWindowController` and forwards
3. `BrowserWindowController.swift` — method that forwards to `MainSplitViewController`
4. `MainSplitViewController.swift` — actual behavior

---

## 7. Feature map

### Tabs
- Tabs are `@Observable` with their own `WKWebView`. Selected tab's web view
  is the only one in the view hierarchy; others stay alive but detached.
- Tab sessions (URLs + titles) are saved on quit via `TabSessionStore` — **unpinned only**.
- Pinned tabs are a separate SwiftData store. Matched by URL (not UUID) because
  fresh `BrowserTab`s on restore get new UUIDs.

### Reader Mode ("Easy Read", ⇧⌘E)
- Injects `Readability.js` via `evaluateJavaScript`, parses into `ReaderArticle`
- Renders via `loadHTMLString` into a dedicated `WKWebView` inside `ReaderModeView`
- 4 themes (light/sepia/gray/dark) × 4 fonts (New York/Georgia/System/Mono), persisted
- **Per-tab state**: `BrowserTab.readerArticle + readerParsedForURL`. Tab
  switch = hide; switch back = remount from cache (no re-parse). URL change
  invalidates cache.
- Link inside reader → opens in new tab (same behavior as Safari). Same-document
  anchor links (`#section`) stay in the reader.
- Exit via X / ESC / click outside.

### Focus Mode = "Zen Mode" (⇧⌘F)
- Hides **both** address bar + sidebar
- Top 10 pt hover zone (`HoverDetectorView`) auto-reveals the address bar
  when cursor enters; re-hides after 0.3 s leave delay
- Address bar button (`circle.circle` icon) also triggers Zen Mode
- Traffic lights are hidden when **both** sidebar + address bar are hidden,
  reappear on hover reveal

### Downloads
- `decidePolicyFor navigationResponse` returns `.download` for
  `Content-Disposition: attachment`, configured MIME types, or non-renderable
  content
- `DownloadConfirmationView` shows a custom modal alert BEFORE any file is written
- User allows → destination is computed with `(1)`, `(2)` collision handling in `~/Downloads/`
- Progress tracked via KVO on `WKDownload.progress.completedUnitCount`
- **Floating toast** (bottom-right) shows active + recently-finished items.
  Auto-dismisses 6 s after all terminal. X button hides entire toast (not cancel).
  Hover on progress bar reveals Pause/Resume + Cancel buttons.
- **Sidebar Downloads view** (⌥⌘L toggle) replaces tab list. Grouped by date.
  Per-row Pause/Resume/Cancel (no hover required).
- Badge on Downloads button shows count of currently-downloading items.
- Pause = `WKDownload.cancel { resumeData in }` + save data to the item. Resume = `WKWebView.resumeDownload(fromResumeData:)`.
- On app quit → all active downloads are cancelled (partial files removed).

### HTTP Authentication
- `WKNavigationDelegate.webView(_:didReceive:completionHandler:)` shows `AuthenticationDialogView`
- Server trust challenges auto-accepted
- Basic/Digest auth prompts the custom dialog; credential persistence = `.forSession`
- Max 3 retries before auto-cancel

### File Upload
- `WKUIDelegate.webView(_:runOpenPanelWith:...)` wraps `NSOpenPanel` as a
  sheet on the browser window with a black dim overlay over the web content

### Permissions (camera, mic, location)
- Per-site `PermissionPolicy` = `.ask` / `.allow` / `.deny`, persisted per
  `SitePermissionType`. See `SitePermissionStore`. `nil` = never requested
  (column hidden in settings).
- `PermissionBannerView` is the prompt UI

### Error pages
- Custom SwiftUI overlay with funny per-category messages (no internet / DNS / timeout / server / SSL / generic)
- Triggered from `didFailProvisionalNavigation` + `didFail`. **Filtered out**: `NSURLErrorCancelled` (-999) and `WebKitErrorDomain` code 102 (which fires whenever a navigation is turned into a download).
- `Try Again` button loads `tab.url` explicitly (not `webView.reload()`), because for provisional failures the web view's "last committed URL" and the intended URL differ.

### Reader Mode blur / Shortcuts overlay blur
- Uses the private `CAFilter` API via `GaussianBlurView` for **live, tunable**
  Gaussian blur. Public `NSVisualEffectView` has fixed-radius materials and
  doesn't give you a live tunable blur. Core Image is snapshot-only.
- `CAFilter` is private API — App Store rejects it. Fine for Developer ID /
  internal. The runtime lookup via `NSClassFromString("CAFilter")` means it
  silently falls back to no blur if Apple removes the class.

### Pinned tabs (drag-and-drop)
- Pinned tab grid at the top of the sidebar
- Drag a tab into the pinned grid → pin it (identity-matched by URL for persistence)
- Drag a pinned tab into the tab list → unpin it
- Pin button appears on hover on regular tabs
- `tabs = Array(tabs)` trick is used after `pinTab/unpinTab` to force `@Observable` to emit — mutating a property on an element of an array does not trigger diffing.

### Shortcuts overlay (⌘/)
- SwiftUI cheat sheet with all shortcuts, grouped by category. Chrome-edge design.
- Live Gaussian blur behind it (same `GaussianBlurView` as reader mode)
- ESC / click outside / X button to dismiss

### Settings
- Custom chrome window, hidden title bar, custom traffic lights
- 5 tabs: General, Privacy, Permissions, Shortcuts, About
- Non-resizable (800×450 / 800×500)
- General → "Default Browser" button → `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for http + https. The Info.plist declares `CFBundleURLTypes` so the OS will accept us as a default browser candidate.

### Full-screen video
- `WKWebViewConfiguration.preferences.isElementFullscreenEnabled = true` + private `fullScreenEnabled` preference
- `BrowserWindow.collectionBehavior = [.fullScreenPrimary]`
- Tab switch while a video is in element fullscreen: `evaluateJavaScript("if (document.fullscreenElement) { document.exitFullscreen(); }")` runs on the old web view in `displayTab`

### Closing a tab stops media
- `webView.pauseAllMediaPlayback()` + load `about:blank` before removing — both needed because Web Audio contexts aren't covered by `pauseAllMediaPlayback()`

---

## 8. Known gotchas / bug catalog

These are bugs that were fixed after real debugging. Don't re-introduce them.

### 1. `tab.url` reverts to old URL on failed navigation

**Symptom**: Navigate to a URL that fails (`http://localhost`, DNS fails). User
clicks Try Again → reloads the previous page instead of the failed URL.

**Root cause**: WKWebView reverts `webView.url` to the last committed URL when
a provisional navigation fails. KVO fires, observer writes it into `tab.url`.

**Fix**: `BrowserTab` has `isProvisionalNavigationInFlight` flag. Set `true`
in `didStartProvisionalNavigation`, cleared in `didCommit/didFinish/didFail`.
While true, the `webView.url` KVO observer IGNORES changes. `decidePolicyFor
navigationAction` sets `tab.url = navigationAction.request.url` so the address
bar reflects the target URL immediately. **Try Again** must call
`webView.load(URLRequest(url: tab.url))`, not `webView.reload()`.

### 2. Download address bar shows download URL after confirmation

**Symptom**: Click download link → address bar updates to download URL
(correct). Click Allow/Deny → address bar stays on download URL (wrong).

**Root cause**: Optimistic `tab.url = downloadURL` in `decidePolicyFor
navigationAction` never gets reverted because the navigation becomes a
download (never commits).

**Fix**: Revert in TWO places:
1. `navigationAction/Response:didBecome download:` — `tab.url = webView.url`
2. Inside `WKDownloadDelegate.decideDestinationUsing` completion — same
   revert, belt-and-suspenders

Also: do not guard with `if let committedURL = webView.url` — for fresh tabs
the committed URL is nil, and we WANT to clear `tab.url` in that case
(address bar goes blank, not showing the download URL).

### 3. Error page shown for downloads

**Symptom**: Click a zip download → error page flashes.

**Root cause**: `didFailProvisionalNavigation` fires with
`WebKitErrorDomain` code 102 (`FrameLoadInterruptedByPolicyChange`) after
returning `.download` from `decidePolicyFor navigationResponse`. Our error
classifier treated it as a real error.

**Fix**: In `BrowsingError.from(_:)`, explicitly return `nil` for that
error. Same treatment as `NSURLErrorCancelled` (-999).

### 4. Arrow keys in YouTube beep

**Symptom**: Arrow keys seek the video but the system plays an error beep.

**Root cause**: WKWebView processes the keys but doesn't mark them as
consumed. The event bubbles up through the responder chain to `NSWindow`'s
`keyDown(with:)`, which calls `noResponder(for:)` → `NSBeep()`.

**Fix**: Override `keyDown(with:)` on `BrowserWindow` to do NOTHING (no super
call, no beep). Menu shortcuts are unaffected because they go through
`performKeyEquivalent(with:)` earlier in the chain.

### 5. Address bar auto-focuses on launch

**Symptom**: Window opens → URL text field has focus immediately.

**Root cause**: AppKit's default key-view loop selects the first focusable
view (the URL field) as initial first responder.

**Fix**: `window.initialFirstResponder = splitVC.view` (plain NSView, doesn't
accept first responder) + a `didBecomeKeyNotification` observer that clears
any text-field first responder.

### 6. Pin/unpin doesn't reflect instantly

**Symptom**: Sidebar doesn't update when you pin/unpin until you relaunch.

**Root cause**: Mutating `tab.isPinned` on an element of `tabs` array does
NOT emit an `@Observable` change for the array (only for the individual tab
object, and the sidebar observes the array via `pinnedTabs`/`unpinnedTabs`
computed properties).

**Fix**: After `pinTab`/`unpinTab`, do `tabs = Array(tabs)` to force the
array itself to be re-assigned. This re-emits observation.

### 7. Inspector close doesn't work

**Symptom**: ⌘⌥C opens the inspector. Pressing it again does nothing.

**Root cause**: When the inspector window has focus, the menu shortcut
doesn't fire (inspector lives in a separate in-process window that doesn't
propagate menu key events back to our app).

**Fix**: `BrowserApplication` subclass of `NSApplication`. Override
`sendEvent(_:)` to intercept ⌘⌥C at the app level — before any window sees it.

### 8. Dismiss on in-progress download row re-adds itself

**Symptom**: Click minus on a download toast row → it briefly disappears
then comes back.

**Root cause**: `refreshDownloadsToast()` re-added all in-progress downloads
to `toastVisibleIDs` unconditionally on each refresh.

**Fix**: Two sets — `toastVisibleIDs` (currently shown) and `toastKnownIDs`
(ever-shown). Only BRAND-NEW downloads (`!toastKnownIDs.contains(id)`) get
auto-added. Dismiss removes from `toastVisibleIDs` but keeps in
`toastKnownIDs` so refresh doesn't re-add.

### 9. Reader mode overlay persists across tab switches

**Symptom**: Enable reader on Tab A, switch to Tab B → reader overlay shows
Tab A's article on top of Tab B's content.

**Fix**: Reader state (`readerArticle`, `readerParsedForURL`) moved to
`BrowserTab`. `MainSplitViewController.syncReaderModeForSelectedTab()` is
called on every tab switch — unmounts the old overlay, remounts a new one
from the current tab's cached article if present.

### 10. AsyncImage fails to decode

**Symptom**: `Image(data:)` returns nil.

**Usual cause**: Server returned HTML (error page) or SVG. Check first 4
bytes: `3c` = HTML/SVG. `NSImage(data:)` doesn't decode SVG.

**Fix in the fetcher**: Check MIME type prefix `"image/"` in addition to
200 status.

---

## 9. Dialog / overlay patterns

When you need to show a modal-ish UI over the web content, follow this pattern
(used by `PermissionBannerView`, `AuthenticationDialogView`, `DownloadConfirmationView`):

1. AppKit `NSView` subclass
2. `wantsLayer = true`, `chromeBg` background, rounded 14, `borderLight` stroke, subtle drop shadow via `layer.shadow*`
3. Expose `onAllow`, `onDeny` closures
4. Add to `WebViewController.view` as a subview
5. Center via frame math in `view.bounds`
6. Fade in: `alphaValue = 0` → animate to 1 over 0.2 s
7. On tap: fade out → `removeFromSuperview()`

For SwiftUI overlays (reader, error page, shortcuts overlay):

1. SwiftUI view
2. `NSHostingController` wrapper
3. Add to `contentContainerView` or `view` depending on whether you want to
   cover the whole window vs just the web page area
4. Auto Layout constraints for positioning
5. For reader-style overlays on the web page only, insert BELOW `cornerMaskView`
   so rounded corners clip the overlay

---

## 10. SwiftData recipe (add a new @Model)

1. Create `MyModel.swift` with `@Model` decorator
2. Create `MyModelStore.swift` mirroring `HistoryStore`/`DownloadStore`:
   - `@Observable @MainActor`
   - Own `ModelContainer` via `ModelConfiguration("MyModel", url: myStoreURL)`
   - Where `myStoreURL` lives at `Application Support/Blur-Browser/MyModel.store`
     (DO NOT use default.store — different schemas collide)
3. CRUD methods: `add`, `update`, `remove`, `removeAll`, `fetchAll`
4. Call `refresh()` after every mutation to update the in-memory mirror
5. Wire it into `BrowserWindowController` (one instance per window)

---

## 11. Adding a new keyboard shortcut

1. `Browse/App/AppMenuBuilder.swift` — `addItem(to: ..., key: "X", modifiers: [...], target: delegate)`
2. `Browse/App/AppDelegate.swift` — add `@objc func` handler
3. `Browse/Window/BrowserWindowController.swift` — add forwarding method
4. `Browse/Window/MainSplitViewController.swift` (or target VC) — add behavior
5. `Browse/Shared/ShortcutsCatalog.swift` — add to the catalog (for ⌘/ cheat sheet)
6. `Browse/Settings/ShortcutsSettingsView.swift` — add to the settings table

If the shortcut MUST work while an in-process non-main window has focus
(e.g., Web Inspector window), ALSO intercept it in
`Browse/App/main.swift` `BrowserApplication.sendEvent(_:)`.

---

## 12. Adding a new feature — checklist

Before writing a line of code:

1. Is there an `@Observable` that owns this state? If yes, extend it. If
   no, create one in the relevant subsystem folder.
2. Is it per-tab or global? Per-tab → add properties to `BrowserTab`. Global
   → add to a dedicated store.
3. Does it need persistence? If short-lived / fine to lose on quit,
   in-memory only. Otherwise pick: UserDefaults (small scalar), JSON file
   (lists, ordered), SwiftData (relational / many items / need queries).
4. Does the UI need keyboard shortcuts? Follow §11 above.
5. Does it need to survive across tab switches? Store state on the
   `BrowserTab`, then sync on `syncXForSelectedTab()` from the polling loop.
6. Does it overlay the web content? Follow §9.
7. Does it change the sidebar mode? Use `SidebarState.tabAreaMode`.

### Before shipping

- Does it handle sandbox? File APIs need entitlements. Downloads + file
  upload are already wired; new file access usually isn't.
- Will it break default-browser registration? Anything in Info.plist about
  URL schemes needs careful handling.
- Did you preserve the "no beep on unhandled key" behavior?
- Did you handle failed-navigation edge cases (downloads, SSL, redirects)?

---

## 13. What NOT to do

- **Don't** use `NSSplitViewController` or `NSToolbar` with custom items
- **Don't** set `NSHostingView` as `self.view` directly
- **Don't** use `ObservableObject` or `@StateObject`
- **Don't** move the tab bar to the top (it's a vertical sidebar on the LEFT)
- **Don't** use `WKWebView` inside SwiftUI via `WKWebViewRepresentable` — host it in AppKit
- **Don't** add 3rd-party dependencies
- **Don't** hardcode colors — use `Colors` tokens in `Shared/Constants.swift`
- **Don't** remove `BrowserWindow.keyDown(with:)` empty override — it prevents beeps
- **Don't** merge SwiftData schemas into a single `default.store`
- **Don't** forget `target = delegate` on menu items that call AppDelegate methods
- **Don't** call `webView.reload()` for the "Try Again" path — load `tab.url` explicitly
- **Don't** re-parse the reader article on every tab switch — use the cached `tab.readerArticle`

---

## 14. Private / undocumented APIs used

| API | Where | Why |
|---|---|---|
| `WKWebView._inspector` selector | `BrowserWindowController.toggleInspector()` | Programmatic inspector open/close |
| `preferences.setValue(true, forKey: "developerExtrasEnabled")` | `BrowserTab.makeFilterConfiguration()` | Enable inspector UI |
| `preferences.setValue(true, forKey: "fullScreenEnabled")` | same | Belt-and-suspenders for element fullscreen |
| `CAFilter` via `NSClassFromString` | `GaussianBlurView` | Live tunable Gaussian blur (no public API exists) |
| `NSVisualEffectView.material = .sidebar/.selection/etc.` | (not used anymore, reader uses CAFilter) | — |

---

## 15. Project-level oddities

- **Two `.xcodeproj` files** may exist (`Blur-Browser.xcodeproj` and legacy
  `Browse.xcodeproj`). Always build against `Blur-Browser.xcodeproj` with
  scheme `Blur-Browser`.
- Bundle display name is "Blur-Browser" (hyphenated). Settings / about / code references all use `AppConstants.appName` which evaluates to `"Blur-Browser"`.
- Hardened Runtime is enabled (Debug + Release). Required for macOS to accept us as default browser.
- Sandbox is enabled. This means SwiftData stores go under
  `~/Library/Containers/com.Blur-Browser.app/Data/Library/Application Support/Blur-Browser/`, not the user-visible Application Support.

---

## 16. When you're stuck

- Check git log — a lot of bugs have detailed commit messages
- Search this file for the symptom (§8 bug catalog)
- Look for prior art in neighboring files before inventing a new pattern
- Respect the polling loop — it's the canonical bridge between `@Observable`
  state and AppKit. Don't invent a notification/Combine alternative.

---

**Last updated:** 2026-04-21 (downloads pause/resume in sidebar; badge count;
⌥⌘L toggle; Zen Mode rename; reader mode per-tab state; CAFilter blur).
