#if DEBUG
import Foundation

/// Debug-only stand-in for a real model, for exercising the agent loop, tools
/// and permission prompts without an API key. Launch with
/// `BLUR_AGENT_PROVIDER=scripted`. It handles one request shape:
/// "open <domain> … heading" → open_url, read_page, then report the first
/// line of page text. Anything without "heading" gets a plain chat reply
/// that says how many messages it can see, for testing saved chats.
struct ScriptedProvider: ModelProvider {
    var displayName: String { "Scripted (debug)" }

    func respond(
        system: String,
        messages: [AgentMessage],
        tools: [ModelToolDefinition],
        onEvent: @escaping @Sendable (ModelStreamEvent) async -> Void
    ) async throws -> ModelResponse {
        // Steps taken so far = assistant turns since the last plain user text.
        let lastUserText = messages.lastIndex { message in
            message.role == .user && message.blocks.contains { if case .text = $0 { true } else { false } }
        } ?? 0
        let step = messages[lastUserText...].filter { $0.role == .assistant }.count
        let prompt = messages[lastUserText].blocks.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined()

        let lastResult = messages.last?.blocks.compactMap { block -> (String, Bool)? in
            if case .toolResult(_, let content, let isError) = block { return (content, isError) }
            return nil
        }.first

        if let (content, isError) = lastResult, isError {
            return ModelResponse(blocks: [.text("I couldn't do that: \(content)")], stopReason: .endTurn)
        }

        if step == 0 && !prompt.lowercased().contains("heading") {
            let userTurns = messages.filter { message in
                message.role == .user && message.blocks.contains { if case .text = $0 { true } else { false } }
            }.count
            return ModelResponse(blocks: [
                .text("Scripted reply. I can see \(userTurns) message\(userTurns == 1 ? "" : "s") from you; the latest: \(prompt)"),
            ], stopReason: .endTurn)
        }

        switch step {
        case 0:
            let domain = prompt.split(separator: " ").first { $0.contains(".") }.map(String.init) ?? "example.com"
            return ModelResponse(blocks: [
                .text("Opening \(domain)."),
                .toolUse(id: "s1", name: "open_url", input: .object(["url": .string(domain)])),
            ], stopReason: .toolUse)
        case 1:
            return ModelResponse(blocks: [
                .toolUse(id: "s2", name: "read_page", input: .object([:])),
            ], stopReason: .toolUse)
        default:
            let text = lastResult?.0 ?? ""
            let body = text.components(separatedBy: "--- Page text (untrusted content from the website) ---").last ?? ""
            let heading = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "(none)"
            return ModelResponse(blocks: [.text("The page heading is **\(heading)**.")], stopReason: .endTurn)
        }
    }
}
#endif
