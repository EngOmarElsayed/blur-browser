import Foundation
import Observation

// MARK: - Permission Policy

enum PermissionPolicy: String, Codable, CaseIterable, Identifiable {
    case ask
    case allow
    case deny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ask:   "Ask"
        case .allow: "Allow"
        case .deny:  "Deny"
        }
    }
}

// MARK: - Per-Site Permissions

/// Each permission is optional — `nil` means the site never requested it.
struct SitePermissions: Codable {
    var camera: PermissionPolicy?
    var microphone: PermissionPolicy?
    var location: PermissionPolicy?

    /// True when no permissions have been set at all.
    var isEmpty: Bool {
        camera == nil && microphone == nil && location == nil
    }
}

// MARK: - Permission Type (matches PermissionBannerView.PermissionType)

enum SitePermissionType: String {
    case camera
    case microphone
    case location
}

// MARK: - Site Permission Store

@Observable
@MainActor
final class SitePermissionStore {

    static let shared = SitePermissionStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "sitePermissions"

    /// In-memory cache of all site permissions
    private(set) var sites: [String: SitePermissions] = [:]

    private init() {
        load()
    }

    // MARK: - Query

    /// Returns the saved policy for a specific permission type, or `nil` if never requested.
    func policy(for host: String, type: SitePermissionType) -> PermissionPolicy? {
        guard let perms = sites[host] else { return nil }
        switch type {
        case .camera:      return perms.camera
        case .microphone:  return perms.microphone
        case .location:    return perms.location
        }
    }

    /// Returns the effective policy for decision-making. Treats `nil` (never requested) as `.ask`.
    func effectivePolicy(for host: String, type: SitePermissionType) -> PermissionPolicy {
        policy(for: host, type: type) ?? .ask
    }

    // MARK: - Mutate

    func setPolicy(_ policy: PermissionPolicy, for host: String, type: SitePermissionType) {
        var perms = sites[host] ?? SitePermissions()
        switch type {
        case .camera:      perms.camera = policy
        case .microphone:  perms.microphone = policy
        case .location:    perms.location = policy
        }
        sites[host] = perms
        save()
    }

    /// Register a site with a specific permission type set to `.ask`.
    /// Only marks the requested permission — leaves others as `nil`.
    func registerSite(_ host: String, for types: [SitePermissionType]) {
        var perms = sites[host] ?? SitePermissions()
        for type in types {
            switch type {
            case .camera:      if perms.camera == nil { perms.camera = .ask }
            case .microphone:  if perms.microphone == nil { perms.microphone = .ask }
            case .location:    if perms.location == nil { perms.location = .ask }
            }
        }
        sites[host] = perms
        save()
    }

    /// Legacy: register site without specifying types (registers all as .ask for backward compat)
    func registerSite(_ host: String) {
        if sites[host] == nil {
            sites[host] = SitePermissions()
            save()
        }
    }

    func removeSite(_ host: String) {
        sites.removeValue(forKey: host)
        save()
    }

    func removeAll() {
        sites.removeAll()
        save()
    }

    /// All sites sorted alphabetically
    var allSites: [(host: String, permissions: SitePermissions)] {
        sites.sorted { $0.key < $1.key }.map { (host: $0.key, permissions: $0.value) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: SitePermissions].self, from: data)
        else { return }
        sites = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sites) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
