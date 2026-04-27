import Foundation
import Security
import os

@MainActor
final class PasswordStore {
    private let log = Logger(subsystem: "com.browse.app", category: "PasswordStore")
    private let labelPrefix = "Browse — "

    @discardableResult
    func save(_ cred: Credential) -> Bool {
        let item = baseAttributes(site: cred.site, username: cred.username)
            .merging([
                kSecValueData as String: Data(cred.password.utf8),
                kSecAttrLabel as String: labelPrefix + cred.site,
                kSecAttrGeneric as String: idMetadata(cred.id),
                kSecAttrSynchronizable as String: kCFBooleanTrue!,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            ]) { current, _ in current }

        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Same site+username already exists; treat save as update.
            return update(site: cred.site, username: cred.username, password: cred.password)
        }
        if status != errSecSuccess {
            log.error("SecItemAdd failed: \(status, privacy: .public)")
            return false
        }
        return true
    }

    @discardableResult
    func update(id: UUID, password: String) -> Bool {
        guard let cred = lookupAll().first(where: { $0.id == id }) else { return false }
        return update(site: cred.site, username: cred.username, password: password)
    }

    @discardableResult
    private func update(site: String, username: String, password: String) -> Bool {
        let query = baseAttributes(site: site, username: username)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(password.utf8),
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status != errSecSuccess {
            log.error("SecItemUpdate failed: \(status, privacy: .public)")
            return false
        }
        return true
    }

    func lookup(forSite site: String) -> [Credential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: site,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { credential(from: $0) }
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard let cred = lookupAll().first(where: { $0.id == id }) else { return false }
        let query = baseAttributes(site: cred.site, username: cred.username)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            log.error("SecItemDelete failed: \(status, privacy: .public)")
            return false
        }
        return true   // errSecItemNotFound is treated as a successful delete (already gone)
    }

    // MARK: - Private

    private func baseAttributes(site: String, username: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: site,
            kSecAttrAccount as String: username,
        ]
    }

    private func lookupAll() -> [Credential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { credential(from: $0) }
    }

    private func credential(from item: [String: Any]) -> Credential? {
        guard
            let site = item[kSecAttrServer as String] as? String,
            let username = item[kSecAttrAccount as String] as? String,
            let data = item[kSecValueData as String] as? Data,
            let password = String(data: data, encoding: .utf8)
        else { return nil }

        let id = decodeId(from: item[kSecAttrGeneric as String] as? Data) ?? UUID()
        let createdAt = item[kSecAttrCreationDate as String] as? Date ?? .now
        let updatedAt = item[kSecAttrModificationDate as String] as? Date ?? createdAt

        // Filter out items we didn't write (some other app's kSecClassInternetPassword
        // entries on the same keychain). We always write a "Browse — " prefix label.
        if let label = item[kSecAttrLabel as String] as? String, !label.hasPrefix(labelPrefix) {
            return nil
        }

        return Credential(id: id, site: site, username: username, password: password,
                          createdAt: createdAt, updatedAt: updatedAt)
    }

    private func idMetadata(_ id: UUID) -> Data {
        try! JSONSerialization.data(withJSONObject: ["id": id.uuidString])
    }

    private func decodeId(from data: Data?) -> UUID? {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let raw = obj["id"], let id = UUID(uuidString: raw) else { return nil }
        return id
    }
}
