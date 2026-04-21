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
        if let raw = defaults.string(forKey: Keys.themeID),
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
