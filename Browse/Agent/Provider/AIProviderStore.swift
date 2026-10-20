import Foundation
import Observation

// MARK: - Provider configuration

enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openAICompatible = "openai"
    case gemini

    var label: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAICompatible: "OpenAI-compatible"
        case .gemini: "Google Gemini"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com/v1"
        case .openAICompatible: "https://api.openai.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: ClaudeProvider.defaultModel
        case .openAICompatible: "gpt-4.1-mini"
        case .gemini: "gemini-2.5-flash"
        }
    }
}

/// One model endpoint the agent can use. Holds no secrets: the API key lives
/// in the Keychain under `keychainAccount`.
struct AIProviderConfig: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var label: String
    var kind: AIProviderKind
    var baseURL: String
    var model: String
    /// Whether to offer the browser tools. Off for endpoints that don't
    /// support tool calls; the agent then works as page-aware chat.
    var supportsTools: Bool
    var keychainAccount: String

    init(
        id: UUID = UUID(),
        label: String,
        kind: AIProviderKind,
        baseURL: String? = nil,
        model: String? = nil,
        supportsTools: Bool = true,
        keychainAccount: String? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.model = model ?? kind.defaultModel
        self.supportsTools = supportsTools
        self.keychainAccount = keychainAccount ?? "provider-\(id.uuidString)"
    }

    /// Loopback and private-network endpoints (local model servers) work
    /// without a key; hosted APIs need one.
    /// The stock "Local model" entry exactly as `defaultProviders()` creates it.
    var isStockLocalPlaceholder: Bool {
        kind == .openAICompatible && baseURL == "http://127.0.0.1:8080/v1" && model == "local"
    }

    var isLocal: Bool {
        guard let host = URL(string: baseURL)?.host() else { return false }
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 127 || octets[0] == 10
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
    }

    @MainActor
    func makeProvider() -> any ModelProvider {
        let key = KeychainStore.read(account: keychainAccount)
        switch kind {
        case .anthropic:
            return ClaudeProvider(model: model, baseURL: baseURL, apiKey: key)
        case .openAICompatible:
            return OpenAICompatibleProvider(config: self, apiKey: key)
        case .gemini:
            return GeminiProvider(config: self, apiKey: key)
        }
    }
}

// MARK: - Store

/// The configured providers and which one the agent uses. Persisted to
/// UserDefaults (no secrets); keys go through `setKey` into the Keychain.
@Observable
@MainActor
final class AIProviderStore {
    static let shared = AIProviderStore()

    private static let providersKey = "ai.providers"
    private static let activeKey = "ai.activeProviderID"
    private static let legacyClaudeModelKey = "ai.claude.model"
    private static let assistantMigratedKey = "ai.migratedAssistantJSON"
    private static let legacyBundleMigratedKey = "ai.migratedLegacyBundleDefaults"
    /// The bundle id the app shipped with before signing moved to
    /// Config/Signing.xcconfig. Forks that change the bundle id get a fresh
    /// defaults domain, so providers saved under this one are imported once.
    private static let legacyBundleID = "com.Blur-Browser.app"

    /// The built-in Claude entry keeps the Keychain account the first agent
    /// release used, so an already-saved key still works.
    static let defaultClaudeID = UUID(uuidString: "6B1C0A7E-3F7A-4C61-9D55-0C1A7DE00001")!
    static let legacyAnthropicAccount = "anthropic-api-key"

    private(set) var providers: [AIProviderConfig]
    private(set) var activeID: UUID
    /// Bumped on every Keychain write so views re-read `hasKey`.
    private(set) var keyRevision = 0

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.providersKey),
           let saved = try? JSONDecoder().decode([AIProviderConfig].self, from: data), !saved.isEmpty {
            providers = saved
        } else {
            providers = Self.defaultProviders()
        }
        activeID = defaults.string(forKey: Self.activeKey).flatMap(UUID.init) ?? Self.defaultClaudeID
        if !providers.contains(where: { $0.id == activeID }) { activeID = providers[0].id }
        migrateAssistantConfigIfNeeded()
        migrateLegacyBundleDefaultsIfNeeded()
        save()
    }

    var active: AIProviderConfig {
        providers.first { $0.id == activeID } ?? providers[0]
    }

    func makeActiveProvider() -> any ModelProvider {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BLUR_AGENT_PROVIDER"] == "scripted" {
            return ScriptedProvider()
        }
        #endif
        return active.makeProvider()
    }

    // MARK: Mutations

    func select(_ id: UUID) {
        guard providers.contains(where: { $0.id == id }) else { return }
        activeID = id
        save()
    }

    func update(_ config: AIProviderConfig) {
        guard let index = providers.firstIndex(where: { $0.id == config.id }) else { return }
        providers[index] = config
        save()
    }

    @discardableResult
    func add(kind: AIProviderKind, label: String? = nil, baseURL: String? = nil, model: String? = nil, supportsTools: Bool = true) -> AIProviderConfig {
        let config = AIProviderConfig(
            label: label ?? kind.label, kind: kind, baseURL: baseURL, model: model, supportsTools: supportsTools)
        providers.append(config)
        save()
        return config
    }

    func remove(_ id: UUID) {
        guard providers.count > 1, let index = providers.firstIndex(where: { $0.id == id }) else { return }
        let removed = providers.remove(at: index)
        KeychainStore.delete(account: removed.keychainAccount)
        keyRevision += 1
        if activeID == id { activeID = providers[0].id }
        save()
    }

    // MARK: Keys

    func hasKey(_ config: AIProviderConfig) -> Bool {
        _ = keyRevision
        return !(KeychainStore.read(account: config.keychainAccount) ?? "").isEmpty
    }

    /// Whether the provider can be called as configured.
    func isReady(_ config: AIProviderConfig) -> Bool {
        config.isLocal || hasKey(config)
    }

    @discardableResult
    func setKey(_ key: String, for config: AIProviderConfig) -> Bool {
        defer { keyRevision += 1 }
        return KeychainStore.save(key, account: config.keychainAccount)
    }

    func removeKey(for config: AIProviderConfig) {
        KeychainStore.delete(account: config.keychainAccount)
        keyRevision += 1
    }

    // MARK: Persistence

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: Self.providersKey)
        }
        defaults.set(activeID.uuidString, forKey: Self.activeKey)
    }

    private static func defaultProviders() -> [AIProviderConfig] {
        let claudeModel = UserDefaults.standard.string(forKey: legacyClaudeModelKey) ?? ClaudeProvider.defaultModel
        return [
            AIProviderConfig(
                id: defaultClaudeID, label: "Claude", kind: .anthropic, model: claudeModel,
                keychainAccount: legacyAnthropicAccount),
            AIProviderConfig(label: "OpenAI", kind: .openAICompatible),
            AIProviderConfig(label: "Google Gemini", kind: .gemini),
            AIProviderConfig(
                label: "Local model", kind: .openAICompatible,
                baseURL: "http://127.0.0.1:8080/v1", model: "local", supportsTools: false),
        ]
    }

    // MARK: Migration from the Assistant pane

    /// The old Assistant pane kept providers *and API keys* in
    /// `~/Library/Application Support/Blur-Browser/assistant.json`. Import its
    /// providers once, move each key into the Keychain, and delete the file
    /// only after every key is safely stored (otherwise retry next launch).
    private func migrateAssistantConfigIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.assistantMigratedKey) else { return }
        let url = Self.legacyAssistantFileURL
        guard let data = try? Data(contentsOf: url) else {
            defaults.set(true, forKey: Self.assistantMigratedKey)
            return
        }
        guard let legacy = try? JSONDecoder().decode(LegacyAssistantConfig.self, from: data) else {
            // Unreadable: leave the file for the user, don't keep retrying.
            defaults.set(true, forKey: Self.assistantMigratedKey)
            return
        }

        var allKeysStored = true
        var imported: [AIProviderConfig] = []
        for old in legacy.providers {
            let kind = AIProviderKind(rawValue: old.kind) ?? .openAICompatible
            let key = old.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            // Anthropic entries fold into the built-in Claude entry when it
            // has no key yet; an Anthropic entry without a key adds nothing.
            if kind == .anthropic, let claude = providers.first(where: { $0.id == Self.defaultClaudeID }) {
                if key.isEmpty { continue }
                if !hasKey(claude) {
                    allKeysStored = setKey(key, for: claude) && allKeysStored
                    continue
                }
            }
            if providers.contains(where: { $0.id == old.id }) { continue }

            let config = AIProviderConfig(
                id: old.id,
                label: old.label,
                kind: kind,
                baseURL: old.baseURL.isEmpty ? nil : old.baseURL,
                model: old.model.isEmpty ? nil : old.model,
                // Hosted APIs do tool calls; local servers often don't, so
                // they start as chat and the user can opt in.
                supportsTools: kind != .openAICompatible || old.baseURL.contains("api.openai.com"))
            if !key.isEmpty {
                allKeysStored = setKey(key, for: config) && allKeysStored
            }
            imported.append(config)
        }

        guard allKeysStored else { return }
        // Imported entries replace the stock ones of the same kind/endpoint.
        providers.removeAll { stock in
            stock.id != Self.defaultClaudeID && !hasKey(stock)
                && imported.contains { $0.kind == stock.kind && ($0.baseURL == stock.baseURL || stock.isLocal && $0.isLocal) }
        }
        providers.append(contentsOf: imported)
        if let oldActive = imported.first(where: { $0.id == legacy.activeProviderID }) {
            activeID = oldActive.id
        }
        try? FileManager.default.removeItem(at: url)
        defaults.set(true, forKey: Self.assistantMigratedKey)
    }

    // MARK: Migration from the previous bundle id

    /// Imports providers saved under `legacyBundleID` when the app now runs
    /// under a different bundle id. Saved entries win over stock ones; if the
    /// active provider is still the untouched stock "Local model" placeholder,
    /// the first imported local provider takes over.
    private func migrateLegacyBundleDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.legacyBundleMigratedKey) else { return }
        defaults.set(true, forKey: Self.legacyBundleMigratedKey)

        guard Bundle.main.bundleIdentifier != Self.legacyBundleID,
              let legacyDefaults = UserDefaults(suiteName: Self.legacyBundleID),
              let data = legacyDefaults.data(forKey: Self.providersKey),
              let legacy = try? JSONDecoder().decode([AIProviderConfig].self, from: data),
              !legacy.isEmpty
        else { return }

        let imported = legacy.filter { old in !providers.contains { $0.id == old.id } }
        guard !imported.isEmpty else { return }

        let wasOnPlaceholder = active.isStockLocalPlaceholder
        providers.removeAll { stock in
            (stock.isStockLocalPlaceholder && imported.contains(where: \.isLocal))
                || (stock.id != Self.defaultClaudeID && !hasKey(stock)
                    && imported.contains { $0.kind == stock.kind && $0.baseURL == stock.baseURL })
        }
        providers.append(contentsOf: imported)

        if let legacyActive = legacyDefaults.string(forKey: Self.activeKey).flatMap(UUID.init),
           providers.contains(where: { $0.id == legacyActive }) {
            activeID = legacyActive
        } else if wasOnPlaceholder, let local = imported.first(where: \.isLocal) {
            activeID = local.id
        }
        if !providers.contains(where: { $0.id == activeID }) { activeID = providers[0].id }
    }

    static var legacyAssistantFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blur-Browser", isDirectory: true)
            .appendingPathComponent("assistant.json")
    }

    private struct LegacyAssistantConfig: Decodable {
        struct Provider: Decodable {
            var id: UUID
            var label: String
            var kind: String
            var baseURL: String
            var apiKey: String
            var model: String
        }
        var providers: [Provider]
        var activeProviderID: UUID?
    }
}
