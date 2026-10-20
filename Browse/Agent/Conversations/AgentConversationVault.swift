import AppKit
import CryptoKit
import Foundation
import LocalAuthentication
import Observation

/// Settings → AI options for saved chats. UserDefaults holds only these
/// switches; chats and their titles live in the encrypted files.
enum AgentChatSettings {
    static let saveKey = "ai.chats.save"
    static let requireAuthKey = "ai.chats.requireTouchID"
    static let autoLockKey = "ai.chats.autoLockMinutes"

    static var saveConversations: Bool {
        get { UserDefaults.standard.object(forKey: saveKey) == nil || UserDefaults.standard.bool(forKey: saveKey) }
        set { UserDefaults.standard.set(newValue, forKey: saveKey) }
    }

    static var requireAuthentication: Bool {
        get { UserDefaults.standard.object(forKey: requireAuthKey) == nil || UserDefaults.standard.bool(forKey: requireAuthKey) }
        set { UserDefaults.standard.set(newValue, forKey: requireAuthKey) }
    }

    /// Minutes in the background or idle before chats lock. 0 = only on
    /// sleep, screen lock, or Lock Now.
    static var autoLockMinutes: Int {
        get { UserDefaults.standard.object(forKey: autoLockKey) == nil ? 15 : UserDefaults.standard.integer(forKey: autoLockKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoLockKey) }
    }

    static let autoLockChoices: [(minutes: Int, label: String)] = [
        (1, "1 minute"), (5, "5 minutes"), (15, "15 minutes"), (30, "30 minutes"), (60, "1 hour"),
        (0, "Only on sleep or screen lock"),
    ]
}

/// Saved agent chats, one AES-GCM sealed file per conversation under
/// `~/Library/Application Support/Blur-Browser/AgentConversations`. Shared by
/// every window. While locked the key and every decrypted title are dropped
/// from memory; unlocking asks for Touch ID (or the Mac password) first.
@Observable
@MainActor
final class AgentConversationVault {
    static let shared = AgentConversationVault()

    enum State: Equatable {
        /// "Save agent conversations" is off.
        case disabled
        case locked
        case unlocking
        case unlocked
    }

    private(set) var state: State
    /// Newest first. Empty while locked.
    private(set) var summaries: [AgentConversationSummary] = []
    private(set) var keyMode: AgentConversationKeyMode?
    /// Why the last unlock failed, for the locked view.
    private(set) var unlockError: String?
    /// Files that exist but can't be opened with the current key.
    private(set) var unreadableCount = 0

    var isUnlocked: Bool { state == .unlocked }
    /// The most recent chat reopens in one window per launch only, so two
    /// windows don't edit the same chat.
    @ObservationIgnored var hasRestoredOnLaunch = false

    @ObservationIgnored private var key: SymmetricKey?
    @ObservationIgnored private var observers: [Observer] = []
    @ObservationIgnored private var backgroundSince: Date?
    @ObservationIgnored private var idleTimer: Timer?

    private struct Observer {
        weak var owner: AnyObject?
        let onUnlock: @MainActor () -> Void
        let onWillLock: @MainActor () -> Void
    }

    private static let magic = Data("BLURCHAT".utf8)
    private static let fileExtension = "chat"

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppConstants.appName, isDirectory: true)
            .appendingPathComponent("AgentConversations", isDirectory: true)
    }

    private init() {
        state = AgentChatSettings.saveConversations ? .locked : .disabled
        startLockTriggers()
        // Without the Touch ID requirement there's nothing to wait for.
        if state == .locked && !AgentChatSettings.requireAuthentication {
            Task { await unlock() }
        }
    }

    // MARK: - Observers

    /// `onUnlock` runs after chats become readable; `onWillLock` runs while
    /// the key is still available, so callers can save before it's dropped.
    func addObserver(_ owner: AnyObject, onUnlock: @escaping @MainActor () -> Void, onWillLock: @escaping @MainActor () -> Void) {
        observers.removeAll { $0.owner == nil }
        observers.append(Observer(owner: owner, onUnlock: onUnlock, onWillLock: onWillLock))
    }

    // MARK: - Lock & unlock

    func unlock() async {
        guard state == .locked else { return }
        state = .unlocking
        unlockError = nil

        let context = LAContext()
        let requireAuth = AgentChatSettings.requireAuthentication
        if requireAuth {
            do {
                _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "show your saved agent chats")
            } catch {
                state = .locked
                if (error as? LAError)?.code != .userCancel && (error as? LAError)?.code != .appCancel {
                    unlockError = error.localizedDescription
                }
                return
            }
        }

        switch AgentConversationKey.read(context: requireAuth ? context : nil) {
        case .found(let found, let mode):
            key = found
            keyMode = mode
            // The setting changed since the key was stored: re-store it with
            // or without the Keychain's own Touch ID binding.
            if (mode == .biometryBound) != requireAuth && mode != .loginKeychain {
                keyMode = AgentConversationKey.store(found, bindToUserPresence: requireAuth, context: context) ?? mode
            }
        case .notFound:
            let fresh = SymmetricKey(size: .bits256)
            guard let mode = AgentConversationKey.store(fresh, bindToUserPresence: requireAuth, context: context) else {
                state = .locked
                unlockError = "Couldn't save the encryption key to the Keychain."
                return
            }
            key = fresh
            keyMode = mode
        case .failed(let status):
            NSLog("Blur-Browser: couldn't read the chats key (OSStatus %d).", status)
            state = .locked
            unlockError = "The Keychain didn't release the key (error \(status))."
            return
        }

        reloadSummaries()
        state = .unlocked
        for observer in observers where observer.owner != nil { observer.onUnlock() }
    }

    func lock() {
        guard state == .unlocked, AgentChatSettings.requireAuthentication else { return }
        for observer in observers where observer.owner != nil { observer.onWillLock() }
        key = nil
        summaries = []
        unreadableCount = 0
        state = .locked
    }

    /// Applies a change to "Save agent conversations".
    func setSavingEnabled(_ enabled: Bool) {
        AgentChatSettings.saveConversations = enabled
        if enabled {
            guard state == .disabled else { return }
            state = .locked
            if !AgentChatSettings.requireAuthentication { Task { await unlock() } }
        } else {
            if state == .unlocked {
                for observer in observers where observer.owner != nil { observer.onWillLock() }
            }
            key = nil
            summaries = []
            state = .disabled
        }
    }

    /// Applies a change to "Require Touch ID". Turning it off needs Touch ID
    /// first, so someone at an unlocked Mac can't simply switch it off.
    func setRequireAuthentication(_ required: Bool) async -> Bool {
        let context = LAContext()
        if !required {
            do {
                _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "stop requiring Touch ID for saved agent chats")
            } catch {
                return false
            }
        }
        AgentChatSettings.requireAuthentication = required
        if let key, keyMode != .loginKeychain {
            keyMode = AgentConversationKey.store(key, bindToUserPresence: required, context: context) ?? keyMode
        }
        if !required && state == .locked { await unlock() }
        return true
    }

    // MARK: - Conversations

    func save(_ conversation: AgentConversation) {
        guard let key, state == .unlocked else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let plaintext = try encoder.encode(conversation)
            let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: Self.associatedData(conversation.id))
            guard let combined = sealed.combined else { return }
            try ensureDirectory()
            let url = fileURL(conversation.id)
            try (Self.magic + combined).write(to: url, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Blur-Browser: couldn't save an agent chat (%@).", String(describing: type(of: error)))
            return
        }
        let summary = conversation.summary
        summaries.removeAll { $0.id == summary.id }
        summaries.insert(summary, at: 0)
        summaries.sort { $0.updatedAt > $1.updatedAt }
    }

    func load(_ id: UUID) -> AgentConversation? {
        guard let key, state == .unlocked else { return nil }
        return Self.decrypt(fileURL(id), id: id, key: key)
    }

    func rename(_ id: UUID, to title: String) {
        guard var conversation = load(id) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.customTitle = trimmed.isEmpty ? nil : trimmed
        save(conversation)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: fileURL(id))
        summaries.removeAll { $0.id == id }
    }

    /// Removes every saved chat file. Works while locked; no key needed.
    func deleteAll() {
        for url in chatFiles() { try? FileManager.default.removeItem(at: url) }
        summaries = []
        unreadableCount = 0
    }

    var savedCount: Int { chatFiles().count }

    // MARK: - Files

    private func reloadSummaries() {
        guard let key else { return }
        var loaded: [AgentConversationSummary] = []
        var unreadable = 0
        for url in chatFiles() {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let conversation = Self.decrypt(url, id: id, key: key) else {
                unreadable += 1
                continue
            }
            loaded.append(conversation.summary)
        }
        summaries = loaded.sorted { $0.updatedAt > $1.updatedAt }
        unreadableCount = unreadable
    }

    private static func decrypt(_ url: URL, id: UUID, key: SymmetricKey) -> AgentConversation? {
        guard let data = try? Data(contentsOf: url), data.starts(with: magic),
              let box = try? AES.GCM.SealedBox(combined: data.dropFirst(magic.count)),
              let plaintext = try? AES.GCM.open(box, using: key, authenticating: associatedData(id)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentConversation.self, from: plaintext)
    }

    /// Binds each file to its name, so files can't be swapped or renamed
    /// without failing authentication.
    private static func associatedData(_ id: UUID) -> Data {
        Data("blur-agent-chat:\(id.uuidString)".utf8)
    }

    private func fileURL(_ id: UUID) -> URL {
        Self.directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.fileExtension)
    }

    private func chatFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == Self.fileExtension }
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: Self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    // MARK: - Auto-lock

    private func startLockTriggers() {
        let app = NotificationCenter.default
        app.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.backgroundSince = Date() }
        }
        app.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkTimeouts()
                self?.backgroundSince = nil
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lock() }
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkTimeouts() }
        }
    }

    private func checkTimeouts() {
        let minutes = AgentChatSettings.autoLockMinutes
        guard state == .unlocked, minutes > 0 else { return }
        let limit = TimeInterval(minutes * 60)
        if let backgroundSince, Date().timeIntervalSince(backgroundSince) >= limit { return lock() }
        // System-wide time since the last keyboard or mouse event.
        let anyInput = CGEventType(rawValue: ~0)!
        if CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput) >= limit { lock() }
    }
}
