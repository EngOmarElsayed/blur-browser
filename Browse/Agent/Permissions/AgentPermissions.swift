import Foundation
import Observation

/// How much an agent action can change. Ordered: a higher level is riskier.
enum AgentRisk: Int, Comparable, Sendable, CaseIterable {
    /// Reads state only: page text, tab list, scrolling the viewport.
    case readOnly = 0
    /// Changes what a tab shows: open/switch tabs, load a URL, back/forward.
    case navigation = 1
    /// Changes page state: clicking, typing into fields.
    case pageMutating = 2
    /// Sends data to a site: submitting a form or pressing a submit control.
    case formSubmit = 3

    static func < (lhs: AgentRisk, rhs: AgentRisk) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .readOnly: "Read only"
        case .navigation: "Navigation"
        case .pageMutating: "Changes page"
        case .formSubmit: "Submits form"
        }
    }

    var symbol: String {
        switch self {
        case .readOnly: "eye"
        case .navigation: "arrow.triangle.turn.up.right.circle"
        case .pageMutating: "hand.point.up.left"
        case .formSubmit: "paperplane"
        }
    }
}

enum AgentPermissionMode: String, Sendable, Codable {
    /// Default. Every action above read-only needs approval (or a site grant).
    case ask
    /// Never asks. Enabled per window session, only after recorded consent.
    case dangerous
}

/// Per-window agent session. Lives on `BrowserWindowController` and is never
/// persisted, so Dangerous mode and site grants reset on relaunch and don't
/// leak between windows.
@Observable
@MainActor
final class AgentSession {
    let id = UUID()
    let startedAt = Date()
    private(set) var mode: AgentPermissionMode = .ask

    /// Host → highest risk the user allowed without asking on that host.
    private(set) var siteGrants: [String: AgentRisk] = [:]

    enum Decision: Equatable {
        case allowed(reason: String)
        case needsApproval
    }

    func decide(risk: AgentRisk, host: String?) -> Decision {
        if risk == .readOnly { return .allowed(reason: "read-only") }
        if mode == .dangerous { return .allowed(reason: "dangerous mode") }
        if let host, let granted = siteGrants[host], risk <= granted {
            return .allowed(reason: "allowed for \(host) this session")
        }
        return .needsApproval
    }

    func grant(_ risk: AgentRisk, forHost host: String) {
        siteGrants[host] = max(siteGrants[host] ?? .readOnly, risk)
    }

    /// The only way into Dangerous mode: the consent is written to the
    /// append-only log first, and the mode flips only if that write succeeds.
    @discardableResult
    func enableDangerousMode(acknowledgement: String) -> Bool {
        let record = AgentConsentRecord(
            event: "dangerous_mode_enabled",
            mode: .dangerous,
            windowSessionID: id,
            acknowledgement: acknowledgement
        )
        guard AgentConsentLog.append(record) else { return false }
        mode = .dangerous
        return true
    }

    func disableDangerousMode() {
        guard mode == .dangerous else { return }
        mode = .ask
        AgentConsentLog.append(AgentConsentRecord(
            event: "dangerous_mode_disabled",
            mode: .ask,
            windowSessionID: id,
            acknowledgement: nil
        ))
    }
}

// MARK: - Consent log

struct AgentConsentRecord: Codable, Sendable {
    var timestamp = Date()
    let event: String
    let mode: AgentPermissionMode
    let windowSessionID: UUID
    /// The exact statement the user agreed to, for enable events.
    let acknowledgement: String?
    var appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
}

/// Append-only JSON Lines log at
/// `~/Library/Application Support/Blur-Browser/agent-consent-log.jsonl`.
/// Records are only ever appended; the app never rewrites or truncates it.
enum AgentConsentLog {
    static var fileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent(AppConstants.appName, isDirectory: true)
            .appendingPathComponent("agent-consent-log.jsonl")
    }

    @discardableResult
    static func append(_ record: AgentConsentRecord) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(record) else { return false }
        line.append(0x0A)

        let url = fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(
                    atPath: url.path, contents: nil,
                    attributes: [.posixPermissions: 0o600]) else { return false }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            return true
        } catch {
            return false
        }
    }

    static func readAll() -> [AgentConsentRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap {
            try? decoder.decode(AgentConsentRecord.self, from: Data($0))
        }
    }
}
