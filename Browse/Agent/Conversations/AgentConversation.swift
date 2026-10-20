import Foundation

/// A saved agent chat. Encoded to JSON and sealed by `AgentConversationVault`;
/// nothing here is ever written to disk in the clear.
///
/// The stored format is its own set of types rather than the live
/// `AgentMessage` / `AgentChatItem`, so the in-memory types can change
/// without breaking chats saved by an older build.
struct AgentConversation: Codable, Identifiable, Sendable {
    static let formatVersion = 1

    var version = AgentConversation.formatVersion
    let id: UUID
    /// Set when the user renames the chat; otherwise the title comes from the
    /// first user message.
    var customTitle: String?
    let createdAt: Date
    var updatedAt: Date
    /// The provider and model the chat last ran with.
    var providerID: UUID?
    var providerLabel: String?
    var model: String?
    var messages: [StoredMessage]
    var items: [StoredItem]

    var title: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        return Self.autoTitle(from: items)
    }

    var summary: AgentConversationSummary {
        AgentConversationSummary(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt, model: model)
    }

    static func autoTitle(from items: [StoredItem]) -> String {
        guard let first = items.lazy.compactMap({ item -> String? in
            if case .user(let text) = item { return text }
            return nil
        }).first else { return "New chat" }
        let line = first
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? first
        return line.count > 60 ? String(line.prefix(57)).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}

/// What the conversations list shows. Kept in memory only while unlocked.
struct AgentConversationSummary: Identifiable, Sendable, Equatable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var model: String?
}

// MARK: - Transcript (what goes to the model)

struct StoredMessage: Codable, Sendable {
    var role: String
    var blocks: [StoredBlock]
}

struct StoredBlock: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case text, toolUse, toolResult, opaque }
    var kind: Kind
    var text: String?
    var id: String?
    var name: String?
    var json: JSONValue?
    var isError: Bool?
}

// MARK: - Display items (what the pane shows)

enum StoredItem: Codable, Sendable {
    case user(String)
    case assistant(String)
    case action(toolName: String, summary: String, risk: Int, host: String?, status: String, detail: String?)
    case notice(String, isError: Bool)
}

// MARK: - Conversion

extension AgentConversation {
    /// Page text attached by "Include this page" is replaced with this stub,
    /// so the model still knows a page was shown that turn.
    static let droppedPageStub = "[The page text attached to this message wasn't saved.]"
    /// Tool results (mostly read_page output) are cut to this many characters.
    static let maxToolResultLength = 1_500

    static func storedMessages(from transcript: [AgentMessage]) -> [StoredMessage] {
        transcript.map { message in
            StoredMessage(role: message.role.rawValue, blocks: message.blocks.map(storedBlock))
        }
    }

    private static func storedBlock(_ block: AgentContentBlock) -> StoredBlock {
        switch block {
        case .text(let text):
            let kept = text.hasPrefix(AgentController.pageContextPrefix) ? droppedPageStub : text
            return StoredBlock(kind: .text, text: kept)
        case .toolUse(let id, let name, let input):
            return StoredBlock(kind: .toolUse, id: id, name: name, json: input)
        case .toolResult(let id, let content, let isError):
            var kept = content
            if kept.count > maxToolResultLength {
                kept = String(kept.prefix(maxToolResultLength)) + "\n[Trimmed when the chat was saved.]"
            }
            return StoredBlock(kind: .toolResult, text: kept, id: id, isError: isError)
        case .opaque(let vendor, let value):
            return StoredBlock(kind: .opaque, name: vendor, json: value)
        }
    }

    /// The transcript to continue from. A chat saved mid-run can end on an
    /// assistant turn whose tool calls never got results; those get an
    /// "interrupted" result so the next request is valid.
    func restoredTranscript() -> [AgentMessage] {
        var transcript: [AgentMessage] = messages.compactMap { stored in
            guard let role = AgentMessage.Role(rawValue: stored.role) else { return nil }
            let blocks: [AgentContentBlock] = stored.blocks.compactMap { block in
                switch block.kind {
                case .text: return block.text.map { .text($0) }
                case .toolUse:
                    guard let id = block.id, let name = block.name else { return nil }
                    return .toolUse(id: id, name: name, input: block.json ?? .object([:]))
                case .toolResult:
                    guard let id = block.id else { return nil }
                    return .toolResult(toolUseID: id, content: block.text ?? "", isError: block.isError ?? false)
                case .opaque:
                    guard let vendor = block.name, let json = block.json else { return nil }
                    return .opaque(vendor: vendor, json)
                }
            }
            return AgentMessage(role: role, blocks: blocks)
        }
        if let last = transcript.last, last.role == .assistant {
            let pending: [AgentContentBlock] = last.blocks.compactMap {
                if case .toolUse(let id, _, _) = $0 {
                    return .toolResult(toolUseID: id, content: "Interrupted: the chat was closed before this ran.", isError: true)
                }
                return nil
            }
            if !pending.isEmpty { transcript.append(AgentMessage(role: .user, blocks: pending)) }
        }
        return transcript
    }

    /// Streaming rows aren't kept; actions that hadn't finished are saved as
    /// interrupted, so a restored chat never shows a live approval card.
    static func storedItems(from items: [AgentChatItem]) -> [StoredItem] {
        items.compactMap { item in
            switch item.kind {
            case .user(let text): return .user(text)
            case .assistant(let text): return .assistant(text)
            case .streaming: return nil
            case .notice(let text, let isError): return .notice(text, isError: isError)
            case .action(let info):
                let status: String
                var detail: String?
                switch info.status {
                case .done(let allowedBy): status = "done"; detail = allowedBy
                case .denied: status = "denied"
                case .failed(let message): status = "failed"; detail = message
                case .awaitingApproval, .running: status = "failed"; detail = "Interrupted"
                }
                return .action(toolName: info.toolName, summary: info.summary, risk: info.risk.rawValue,
                               host: info.host, status: status, detail: detail)
            }
        }
    }

    func restoredItems() -> [AgentChatItem] {
        items.map { stored in
            switch stored {
            case .user(let text): return AgentChatItem(kind: .user(text))
            case .assistant(let text): return AgentChatItem(kind: .assistant(text))
            case .notice(let text, let isError): return AgentChatItem(kind: .notice(text, isError: isError))
            case .action(let toolName, let summary, let risk, let host, let status, let detail):
                let restoredStatus: AgentChatItem.ActionInfo.Status = switch status {
                case "done": .done(allowedBy: detail)
                case "denied": .denied
                default: .failed(detail ?? "Failed")
                }
                return AgentChatItem(kind: .action(.init(
                    toolName: toolName, summary: summary, risk: AgentRisk(rawValue: risk) ?? .readOnly,
                    host: host, status: restoredStatus)))
            }
        }
    }
}
