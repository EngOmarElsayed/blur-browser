import Foundation

struct AppShortcut: Identifiable {
    let id = UUID()
    let action: String
    let shortcut: String
}

struct ShortcutSection: Identifiable {
    let id = UUID()
    let title: String
    let items: [AppShortcut]
}

/// Single source of truth for the app's keyboard shortcuts, grouped by category.
/// Used by both the shortcuts cheat-sheet overlay and the Settings Shortcuts tab.
enum ShortcutsCatalog {
    static let sections: [ShortcutSection] = [
        ShortcutSection(title: "File", items: [
            AppShortcut(action: "New Tab",          shortcut: "⌘T"),
            AppShortcut(action: "Quick Search",     shortcut: "⌘K"),
            AppShortcut(action: "New Window",       shortcut: "⌘N"),
            AppShortcut(action: "Open Location",    shortcut: "⌘L"),
            AppShortcut(action: "Close Tab",        shortcut: "⌘W"),
        ]),
        ShortcutSection(title: "Edit", items: [
            AppShortcut(action: "Find in Page",     shortcut: "⌘F"),
            AppShortcut(action: "Find Next",        shortcut: "⌘G"),
            AppShortcut(action: "Find Previous",    shortcut: "⇧⌘G"),
            AppShortcut(action: "Copy URL",         shortcut: "⇧⌘C"),
        ]),
        ShortcutSection(title: "View", items: [
            AppShortcut(action: "Toggle Sidebar",   shortcut: "⌘\\"),
            AppShortcut(action: "Toggle Sidebar (Alt)", shortcut: "⇧⌘\\"),
            AppShortcut(action: "Zen Mode",         shortcut: "⇧⌘F"),
            AppShortcut(action: "Toggle Address Bar", shortcut: "⇧⌘A"),
            AppShortcut(action: "Reload",           shortcut: "⌘R"),
            AppShortcut(action: "Hard Reload",      shortcut: "⇧⌘R"),
            AppShortcut(action: "Web Inspector",    shortcut: "⌥⌘C"),
            AppShortcut(action: "Easy Read",        shortcut: "⇧⌘E"),
            AppShortcut(action: "Show Downloads",   shortcut: "⌥⌘L"),
        ]),
        ShortcutSection(title: "History", items: [
            AppShortcut(action: "Show History",     shortcut: "⌘Y"),
            AppShortcut(action: "Back",             shortcut: "⌘["),
            AppShortcut(action: "Forward",          shortcut: "⌘]"),
        ]),
        ShortcutSection(title: "Window", items: [
            AppShortcut(action: "Next Tab",         shortcut: "⇧⌘]"),
            AppShortcut(action: "Previous Tab",     shortcut: "⇧⌘["),
            AppShortcut(action: "Select Tab 1–9",   shortcut: "⌘1 – ⌘9"),
        ]),
        ShortcutSection(title: "App", items: [
            AppShortcut(action: "Settings",         shortcut: "⌘,"),
            AppShortcut(action: "Keyboard Shortcuts", shortcut: "⌘/"),
        ]),
    ]
}
