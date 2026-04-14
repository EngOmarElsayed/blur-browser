# Browse

A native macOS browser built with **AppKit + SwiftUI** hybrid architecture. No Electron, no web wrappers — pure Apple frameworks.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+
## Getting Started

```bash
# Open in Xcode
open Browse.xcodeproj

# Or build from command line
xcodebuild -project Browse.xcodeproj -scheme Browse -configuration Debug build
```

## Architecture

AppKit owns the window, toolbar, and WKWebView hosting. SwiftUI is used for the sidebar, history panel, and quick search overlay — embedded via `NSHostingController`.

```
Browse/
├── App/                    # Entry point, AppDelegate, menu bar
├── Window/                 # Window, window controller, root layout
├── Sidebar/                # SwiftUI tab list (left side)
├── Toolbar/                # Address bar with nav buttons
├── WebContent/             # WKWebView controller + coordinator
├── Search/                 # Quick Search overlay + Find in Page
├── History/                # SwiftData store + history panel (right side)
├── Tab/                    # Tab model, tab manager, session persistence
├── Shared/                 # Design tokens, constants, shortcuts
└── Resources/              # Assets, Info.plist, entitlements
```

### Key Design Decisions

- **One WKWebView per tab** — stored in the `BrowserTab` model, only the active tab's web view is in the view hierarchy.
- **`TabManager` is the source of truth** — all tab state mutations go through it. Sidebar, toolbar, and web view read from it.
- **`@Observable` everywhere** — no `ObservableObject`. All view models use `@Observable` with `@MainActor`.
- **Manual frame layout** for the root view controller — avoids `NSSplitViewController` + `NSHostingController` layout cycle crashes with `fullSizeContentView`.
- **No third-party dependencies** — only Apple frameworks (WebKit, SwiftUI, AppKit, SwiftData).

## Features

### Tab Sidebar (Left)
- Vertical tab list with favicon, title, and close button
- Active tab indicator (blue accent bar)
- Drag-to-reorder
- Right-click context menu (Close, Close Others, Duplicate)
- New tab button at bottom
- Collapsible with animation (⌘+\\)
- Resizable via drag divider

### History Panel (Right)
- Grouped by date (Today, Yesterday, Last 7 Days, etc.)
- Search/filter within history
- Right-click context menu (Open, Open in New Tab, Copy URL, Delete)
- SwiftData persistence
- Collapsible with animation (⌘+Y)
- Resizable via drag divider

### Quick Search (⌘+K)
- Centered overlay on web content area
- Searches open tabs, history, and Google suggestions
- Keyboard navigation (arrow keys + Enter)
- Auto-scrolls to selected result
- ⌘+T opens Quick Search in "new tab" mode — creates a tab on Enter
- Dimming backdrop blocks interaction with web view underneath
- Escape or click outside to dismiss

### Find in Page (⌘+F)
- Floating bar, top-right of web content
- Real-time match highlighting (debounced 300ms)
- Match count display
- Previous/Next navigation (⌘+G / ⌘+Shift+G)
- Uses native `WKWebView.find()` API

### Address Bar
- Editable URL field with lock icon
- Back/Forward/Reload navigation buttons
- Share button (native `NSSharingServicePicker`)
- Restores URL when focus is lost without pressing Enter
- Updates in real-time as pages navigate

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘+T | New Tab (opens Quick Search) |
| ⌘+K | Quick Search (current tab) |
| ⌘+W | Close Tab |
| ⌘+L | Focus & select URL bar |
| ⌘+Shift+C | Copy current URL |
| ⌘+F | Find in Page |
| ⌘+G | Find Next |
| ⌘+Shift+G | Find Previous |
| ⌘+\\ | Toggle Sidebar |
| ⌘+Y | Toggle History Panel |
| ⌘+[ | Back |
| ⌘+] | Forward |
| ⌘+R | Reload |
| ⌘+Shift+R | Hard Reload |
| ⌘+1–9 | Switch to Tab 1–9 |
| ⌘+Shift+] | Next Tab |
| ⌘+Shift+[ | Previous Tab |

## Design Tokens

Colors are defined in `Constants.swift`, derived from the design reference (`Browser.pen`):

| Token | Value | Usage |
|---|---|---|
| `foregroundPrimary` | `#1A1A1A` | Main text |
| `foregroundSecondary` | `#666666` | URL text, subtitles |
| `foregroundMuted` | `#888888` | Icons, placeholders |
| `surfacePrimary` | `#FFFFFF` | Cards, URL bar |
| `surfaceSecondary` | `#F7F8FA` | Toolbar background |
| `sidebarBg` | `#F0F1F3` | Sidebar/history background |
| `accentPrimary` | `#4A9FD8` | Active tab indicator |
| `borderLight` | `#E5E7EB` | Dividers, borders |
| `hoverBg` | `#EAECEF` | Hover states |

Typography: Inter font family, sizes 11–14pt.

## License

Private project.
