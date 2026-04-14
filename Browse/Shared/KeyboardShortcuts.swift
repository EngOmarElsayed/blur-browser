import AppKit

enum KeyboardShortcuts {
    struct Shortcut {
        let key: String
        let modifiers: NSEvent.ModifierFlags
    }

    static let newTab          = Shortcut(key: "t", modifiers: .command)
    static let closeTab        = Shortcut(key: "w", modifiers: .command)
    static let focusSearch     = Shortcut(key: "l", modifiers: .command)
    static let findInPage      = Shortcut(key: "f", modifiers: .command)
    static let findNext        = Shortcut(key: "g", modifiers: .command)
    static let findPrevious    = Shortcut(key: "g", modifiers: [.command, .shift])
    static let toggleSidebar   = Shortcut(key: "\\", modifiers: .command)
    static let goBack          = Shortcut(key: "[", modifiers: .command)
    static let goForward       = Shortcut(key: "]", modifiers: .command)
    static let reload          = Shortcut(key: "r", modifiers: .command)
    static let hardReload      = Shortcut(key: "r", modifiers: [.command, .shift])
    static let nextTab         = Shortcut(key: "]", modifiers: [.command, .shift])
    static let previousTab     = Shortcut(key: "[", modifiers: [.command, .shift])
    static let toggleHistory   = Shortcut(key: "y", modifiers: .command)
}
