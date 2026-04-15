import Foundation
import Observation

// MARK: - Search Engine

enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
    case google
    case duckduckgo
    case bing
    case yahoo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .google:     "Google"
        case .duckduckgo: "DuckDuckGo"
        case .bing:       "Bing"
        case .yahoo:      "Yahoo"
        }
    }

    var searchURL: String {
        switch self {
        case .google:     "https://www.google.com/search?q="
        case .duckduckgo: "https://duckduckgo.com/?q="
        case .bing:       "https://www.bing.com/search?q="
        case .yahoo:      "https://search.yahoo.com/search?p="
        }
    }

    var suggestURL: String {
        switch self {
        case .google:     "https://suggestqueries.google.com/complete/search?client=firefox&q="
        case .duckduckgo: "https://duckduckgo.com/ac/?q="
        case .bing:       "https://api.bing.com/osjson.aspx?query="
        case .yahoo:      "https://search.yahoo.com/sugg/gossip/gossip-us-ura/?command="
        }
    }
}

// MARK: - Settings Store

@Observable
@MainActor
final class SettingsStore {

    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let homepageURL = "settings.homepageURL"
        static let searchEngine = "settings.searchEngine"
        static let restoreTabsOnLaunch = "settings.restoreTabsOnLaunch"
    }

    private init() {}

    var homepageURL: String {
        get { defaults.string(forKey: Keys.homepageURL) ?? "https://www.google.com" }
        set { defaults.set(newValue, forKey: Keys.homepageURL) }
    }

    var searchEngine: SearchEngine {
        get {
            guard let raw = defaults.string(forKey: Keys.searchEngine),
                  let engine = SearchEngine(rawValue: raw)
            else { return .google }
            return engine
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.searchEngine) }
    }

    var restoreTabsOnLaunch: Bool {
        get {
            if defaults.object(forKey: Keys.restoreTabsOnLaunch) == nil { return true }
            return defaults.bool(forKey: Keys.restoreTabsOnLaunch)
        }
        set { defaults.set(newValue, forKey: Keys.restoreTabsOnLaunch) }
    }
}
