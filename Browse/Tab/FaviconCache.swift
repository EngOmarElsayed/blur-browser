import Foundation

/// Disk-backed cache of resolved favicon URLs keyed by host.
///
/// The contract is:
/// - `url(for:)` returns the previously-resolved favicon URL for a host, if any
/// - `setURL(_:for:)` stores a resolved URL and persists to UserDefaults
///
/// The cache treats `google.com` and `gmail.google.com` as distinct hosts —
/// subdomains are not collapsed. Scheme (http/https) is not part of the key
/// since favicons are host-level, not URL-level.
@MainActor
final class FaviconCache {

    static let shared = FaviconCache()

    private let defaults = UserDefaults.standard
    private let storageKey = "settings.faviconCache"

    /// In-memory mirror of the persisted cache. Populated on init, updated on write.
    private var cache: [String: URL] = [:]

    private init() {
        load()
    }

    // MARK: - Public API

    func url(for host: String) -> URL? {
        cache[host]
    }

    func setURL(_ url: URL, for host: String) {
        if cache[host] == url { return }
        cache[host] = url
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let stringDict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        cache = stringDict.compactMapValues { URL(string: $0) }
    }

    private func persist() {
        let stringDict = cache.mapValues { $0.absoluteString }
        guard let data = try? JSONEncoder().encode(stringDict) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
