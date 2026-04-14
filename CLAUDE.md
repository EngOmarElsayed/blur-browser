# Browse — Agent Instructions

## What is this project?

A native macOS browser app using **hybrid AppKit + SwiftUI** architecture. AppKit owns the window, layout, toolbar, and WKWebView hosting. SwiftUI is embedded via `NSHostingController` for sidebar, history panel, and search overlays.

## Build & Run

```bash
# Build
xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build
```

The `.xcodeproj` is managed directly in Xcode — no xcodegen. Add/remove files through Xcode's project navigator.

## Architecture Rules

### AppKit is the host — SwiftUI is embedded
- Never wrap the entire window in SwiftUI
- Never use `NavigationSplitView` or `NSSplitViewController` — the root layout uses **manual frame-based layout** in `MainSplitViewController` (which is an `NSViewController`, not `NSSplitViewController`)
- SwiftUI views are embedded via `NSHostingController` with `sizingOptions = []` to prevent layout cycle crashes
- Never set `NSHostingView` as a view controller's `self.view` directly — always wrap in a plain `NSView` container

### Layout cycle prevention
The combination of `fullSizeContentView` + `NSToolbar` + `NSSplitViewController` + `NSHostingController` causes infinite layout passes on macOS. This project avoids it by:
- Using a plain `NSViewController` (`MainSplitViewController`) with manual `frame` layout in `layoutSubviews()`
- No `NSToolbar` — the address bar is a regular view embedded in the content area
- The `BrowserWindow` uses `.titled + .closable + .miniaturizable + .resizable + .fullSizeContentView` but **no** `.unifiedTitleAndToolbar`

### State management
- **`@Observable`** for all view models — never use `ObservableObject` or `@StateObject`
- **`@MainActor`** on all UI state classes
- **`TabManager`** is the single source of truth for all tab state. Mutations go through its methods only
- One `WKWebView` per tab, stored in `BrowserTab.webView`. Only the active tab's web view is in the view hierarchy

### Keyboard shortcuts
All shortcuts are declared in `Browse/App/AppMenuBuilder.swift`. Every menu item targeting `AppDelegate` must have `target = delegate` set explicitly — otherwise shortcuts fail when `WKWebView` is first responder (the responder chain doesn't reach `AppDelegate`).

## File Map

```
Browse/
├── App/
│   ├── main.swift                     # NSApplication entry point
│   ├── AppDelegate.swift              # App lifecycle, forwards all actions to BrowserWindowController
│   └── AppMenuBuilder.swift           # Full menu bar with all shortcuts (target = delegate on every item)
├── Window/
│   ├── BrowserWindow.swift            # NSWindow subclass, canBecomeKey/canBecomeMain for traffic light colors
│   ├── BrowserWindowController.swift  # Owns TabManager, HistoryStore, wires everything together
│   └── MainSplitViewController.swift  # Root NSViewController — manual frame layout for sidebar/toolbar/webview/history
├── Sidebar/
│   ├── SidebarViewController.swift    # NSViewController wrapping NSHostingController<SidebarView>
│   ├── SidebarView.swift              # SwiftUI vertical tab list
│   └── TabItemView.swift              # SwiftUI individual tab row
├── Toolbar/
│   └── AddressBarViewController.swift # NSViewController — back/forward/URL field/reload/share/more
├── WebContent/
│   ├── WebViewController.swift        # NSViewController hosting WKWebView + find bar + quick search overlay
│   ├── WebViewCoordinator.swift       # WKNavigationDelegate + WKUIDelegate, KVO observations
│   └── WebViewConfiguration.swift     # WKWebViewConfiguration factory
├── Search/
│   ├── QuickSearchPanel.swift         # QuickSearchOverlay — NSHostingView overlay with blocking dim view
│   ├── QuickSearchView.swift          # SwiftUI search UI with fixed 300pt height
│   ├── QuickSearchViewModel.swift     # @Observable — search text, results by UUID, Google suggestions API
│   ├── FindInPageBar.swift            # AppKit NSView — search field + match count + prev/next/close
│   └── FindInPageController.swift     # Drives WKWebView.find() API
├── History/
│   ├── HistoryEntry.swift             # SwiftData @Model — url, title, timestamp, faviconURL
│   ├── HistoryStore.swift             # @Observable — SwiftData CRUD, grouped entries, search
│   ├── HistoryPanelView.swift         # SwiftUI — right-side panel matching sidebar style
│   └── HistorySearchView.swift        # SwiftUI — search field for history filtering
├── Tab/
│   ├── BrowserTab.swift               # @Observable — id, url, title, isLoading, webView instance
│   ├── TabManager.swift               # @Observable — source of truth, add/close/select/navigate
│   └── TabSessionStore.swift          # JSON persistence for tab restore across launches
├── Shared/
│   ├── Constants.swift                # Colors, layout values, typography, app constants, NSColor hex init
│   └── KeyboardShortcuts.swift        # Shortcut struct definitions (currently unused — shortcuts are in AppMenuBuilder)
└── Resources/
    ├── Assets.xcassets/               # AppIcon, AccentColor
    ├── Info.plist
    └── Browse.entitlements            # com.apple.security.network.client
```

## Do NOT

- Do not use `NSSplitViewController` — it causes layout cycles with `NSHostingController`
- Do not use `NSToolbar` with custom view items — causes layout cycles with `fullSizeContentView`
- Do not set `NSHostingView` as `self.view` in a view controller — wrap in a plain `NSView`
- Do not add `target: nil` on menu items that call `AppDelegate` methods — they won't work when WKWebView has focus
- Do not use `ObservableObject` or `@StateObject` — use `@Observable` with `@State`
- Do not put the tab bar at the top — it's a vertical sidebar on the LEFT
- Do not use `WKWebView` inside SwiftUI via representable — host it in `WebViewController` (AppKit)
- Do not add third-party dependencies
- Do not hardcode colors — use the tokens in `Constants.swift`

## Design Reference

The design lives in `/Users/omarelsayed/Documents/Browser.pen`. Colors and component specs are extracted from it. The app uses a light theme:

| Token | Hex | Usage |
|---|---|---|
| foregroundPrimary | #1A1A1A | Main text |
| foregroundSecondary | #666666 | URLs, subtitles |
| foregroundMuted | #888888 | Icons, placeholders |
| surfacePrimary | #FFFFFF | Cards, URL bar bg |
| surfaceSecondary | #F7F8FA | Toolbar bg |
| sidebarBg | #F0F1F3 | Sidebar, history panel bg |
| accentPrimary | #4A9FD8 | Active tab indicator |
| borderLight | #E5E7EB | Dividers, strokes |
| hoverBg | #EAECEF | Hover states |

Font: Inter, sizes 11–14pt. Icons: SF Symbols.

## Observation Loop

`BrowserWindowController.setup()` starts a polling `Task` that checks `tabManager.selectedTabID` and `tabManager.selectedTab?.url` every 50ms. When either changes, it updates the web view display and address bar. This replaces Combine/notification-based observation.

## Quick Search Behavior

- **⌘+K**: Opens/toggles Quick Search overlay on current tab
- **⌘+T**: Opens Quick Search with `navigateInNewTab: true` — creates a new tab when the user presses Enter
- Selection is tracked by `UUID` (`selectedID`), not integer index
- Results are grouped: Switch to Tab → History → Search Suggestions
- `ScrollViewReader` auto-scrolls to the selected result
- `BlockingDimView` intercepts all mouse events to prevent web view interaction while overlay is visible

## History Panel

- Created once in `viewDidLoad`, starts hidden (`isHistoryCollapsed = true`)
- Toggled by flipping the bool and calling `layoutSubviews()` inside `NSAnimationContext`
- Uses `NSHostingController` with `sizingOptions = []`, same pattern as sidebar
- Background: `sidebarBg` to match the left sidebar
- Has its own `ResizeDividerView` for resizing (min 180pt, max 500pt)
