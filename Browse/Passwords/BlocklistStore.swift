import Foundation

/// Tracks sites the user has explicitly opted out of password saving via "Never for this site".
/// Backed by UserDefaults; site keys are eTLD+1 strings from SiteIdentity.
final class BlocklistStore {
    private let defaults: UserDefaults
    private let key = "BrowsePasswordBlocklist"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contains(_ site: String) -> Bool {
        let entries = defaults.stringArray(forKey: key) ?? []
        return entries.contains(site)
    }

    func add(_ site: String) {
        var entries = Set(defaults.stringArray(forKey: key) ?? [])
        entries.insert(site)
        defaults.set(Array(entries).sorted(), forKey: key)
    }

    func remove(_ site: String) {
        var entries = Set(defaults.stringArray(forKey: key) ?? [])
        entries.remove(site)
        defaults.set(Array(entries).sorted(), forKey: key)
    }
}
