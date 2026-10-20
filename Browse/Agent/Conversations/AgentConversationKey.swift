import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Where the conversation key lives, and whether the Keychain itself demands
/// Touch ID (or the Mac password) before handing it out.
enum AgentConversationKeyMode: String, Sendable {
    /// Data-protection Keychain item with a `.userPresence` access control:
    /// the key can't be read without Touch ID or the password.
    case biometryBound
    /// Data-protection Keychain item without an access control.
    case dataProtection
    /// Login (file-based) Keychain item, readable by this app while the Mac is
    /// unlocked. Used when the build's signature lacks the entitlement the
    /// data-protection Keychain needs (a profile-less Apple Development or
    /// ad-hoc build). Touch ID is then enforced by the app before reading.
    case loginKeychain

    var description: String {
        switch self {
        case .biometryBound:
            "The key is in the data-protection Keychain and bound to Touch ID: macOS won't release it without Touch ID or your password."
        case .dataProtection:
            "The key is in the data-protection Keychain, on this Mac only."
        case .loginKeychain:
            "The key is in your login Keychain, on this Mac only. This build can't use the data-protection Keychain, so Blur-Browser asks for Touch ID itself before reading the key."
        }
    }
}

/// The random 256-bit key that seals saved agent chats. Generated once, kept
/// only in the Keychain (its own service and account, never synced) and in
/// memory while chats are unlocked. Never written to disk or logged.
enum AgentConversationKey {
    static let service = "Blur-Browser.AgentConversations"
    static let account = "conversation-key"

    enum ReadResult {
        case found(SymmetricKey, AgentConversationKeyMode)
        case notFound
        /// The Keychain refused (for example, the user cancelled its prompt).
        case failed(OSStatus)
    }

    /// Reads the key. `context` should already be evaluated when Touch ID is
    /// required, so a biometry-bound item doesn't prompt a second time.
    static func read(context: LAContext?) -> ReadResult {
        var query = baseQuery(dataProtection: true)
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let dict = result as? [String: Any], let data = dict[kSecValueData as String] as? Data {
            let mode = (dict[kSecAttrDescription as String] as? String).flatMap(AgentConversationKeyMode.init) ?? .dataProtection
            return .found(SymmetricKey(data: data), mode)
        }
        if status != errSecItemNotFound && status != errSecMissingEntitlement { return .failed(status) }

        var legacy = baseQuery(dataProtection: false)
        legacy[kSecReturnData as String] = true
        legacy[kSecMatchLimit as String] = kSecMatchLimitOne
        result = nil
        status = SecItemCopyMatching(legacy as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return .found(SymmetricKey(data: data), .loginKeychain)
        }
        return status == errSecItemNotFound ? .notFound : .failed(status)
    }

    /// Stores `key`, replacing any existing item. Tries the data-protection
    /// Keychain first (bound to user presence when `bindToUserPresence`), then
    /// falls back to the login Keychain.
    static func store(_ key: SymmetricKey, bindToUserPresence: Bool, context: LAContext?) -> AgentConversationKeyMode? {
        delete()
        let data = key.withUnsafeBytes { Data($0) }

        var item = baseQuery(dataProtection: true)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Blur-Browser agent chats key"
        if bindToUserPresence,
           let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil) {
            item[kSecAttrAccessControl as String] = access
            item[kSecAttrDescription as String] = AgentConversationKeyMode.biometryBound.rawValue
            if let context { item[kSecUseAuthenticationContext as String] = context }
        } else {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            item[kSecAttrDescription as String] = AgentConversationKeyMode.dataProtection.rawValue
        }
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecSuccess { return item[kSecAttrAccessControl as String] != nil ? .biometryBound : .dataProtection }
        NSLog("Blur-Browser: data-protection Keychain unavailable for the chats key (OSStatus %d); using the login Keychain.", status)

        var legacy = baseQuery(dataProtection: false)
        legacy[kSecValueData as String] = data
        legacy[kSecAttrLabel as String] = "Blur-Browser agent chats key"
        legacy[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let legacyStatus = SecItemAdd(legacy as CFDictionary, nil)
        if legacyStatus == errSecSuccess { return .loginKeychain }
        NSLog("Blur-Browser: couldn't store the chats key (OSStatus %d).", legacyStatus)
        return nil
    }

    static func delete() {
        SecItemDelete(baseQuery(dataProtection: true) as CFDictionary)
        SecItemDelete(baseQuery(dataProtection: false) as CFDictionary)
    }

    private static func baseQuery(dataProtection: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        return query
    }
}
