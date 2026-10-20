import Foundation

/// Claude via the Messages API (`POST /v1/messages`) over plain URLSession —
/// there's no official Swift SDK and the project takes no third-party deps.
///
/// The key comes from the Keychain (see `AIProviderConfig.makeProvider`), read
/// fresh for each agent run, so changing it in Settings → AI takes effect on
/// the next message.
struct ClaudeProvider: ModelProvider {
    static let defaultModel = "claude-opus-5-5"
    static let defaultBaseURL = "https://api.anthropic.com/v1"
    static let vendor = "anthropic"

    /// Models that accept `fallbacks: "default"` (server-side refusal fallback).
    private static let fallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    private static let effortModels = fallbackModels.union(["claude-haiku-5-5"])

    let model: String
    let effort: String
    let baseURL: String
    private let apiKey: String?
    var displayName: String { "Claude (\(model))" }

    init(model: String = Self.defaultModel, effort: String = "medium", baseURL: String = Self.defaultBaseURL, apiKey: String?) {
        self.model = model
        self.effort = effort
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func respond(
        system: String,
        messages: [AgentMessage],
        tools: [ModelToolDefinition],
        onEvent: @escaping @Sendable (ModelStreamEvent) async -> Void
    ) async throws -> ModelResponse {
        guard let apiKey, !apiKey.isEmpty else {
            throw ModelProviderError.missingAPIKey
        }
        let base = OpenAICompatibleProvider.normalizeBase(baseURL, fallback: Self.defaultBaseURL)
        guard let endpoint = URL(string: base + "/messages") else {
            throw ModelProviderError.badURL(baseURL)
        }
        let isFirstParty = endpoint.host() == "api.anthropic.com"

        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .number(16000),
            "system": .string(system),
            "messages": .array(messages.map(Self.encode)),
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { tool in
                .object([
                    "name": .string(tool.name),
                    "description": .string(tool.description),
                    "input_schema": tool.inputSchema,
                ])
            })
        }
        // Older models (e.g. ones imported from the Assistant pane) reject `effort`.
        if Self.effortModels.contains(model) {
            body["output_config"] = .object(["effort": .string(effort)])
        }
        let useFallbacks = isFirstParty && Self.fallbackModels.contains(model)
        if useFallbacks {
            body["fallbacks"] = .string("default")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if useFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        let json: JSONValue
        do {
            json = try await ProviderHTTP.postJSON(request)
        } catch {
            throw ProviderHTTP.describe(error, baseURL: baseURL)
        }
        return try Self.decode(json)
    }

    // MARK: - Wire format

    private static func encode(_ message: AgentMessage) -> JSONValue {
        let content: [JSONValue] = message.blocks.compactMap { block in
            switch block {
            case .text(let text):
                return .object(["type": .string("text"), "text": .string(text)])
            case .toolUse(let id, let name, let input):
                return .object([
                    "type": .string("tool_use"), "id": .string(id),
                    "name": .string(name), "input": input,
                ])
            case .toolResult(let id, let content, let isError):
                return .object([
                    "type": .string("tool_result"), "tool_use_id": .string(id),
                    "content": .string(content), "is_error": .bool(isError),
                ])
            case .opaque(let vendor, let raw):
                return vendor == Self.vendor ? raw : nil
            }
        }
        return .object(["role": .string(message.role.rawValue), "content": .array(content)])
    }

    private static func decode(_ json: JSONValue) throws -> ModelResponse {
        guard case .array(let content)? = json["content"] else {
            throw ModelProviderError.decoding("missing content")
        }
        // Every block is kept, in order — thinking blocks must be echoed back
        // unchanged on the next turn, so anything we don't render is opaque.
        let blocks: [AgentContentBlock] = content.map { block in
            switch block["type"]?.stringValue {
            case "text":
                return .text(block["text"]?.stringValue ?? "")
            case "tool_use":
                return .toolUse(
                    id: block["id"]?.stringValue ?? UUID().uuidString,
                    name: block["name"]?.stringValue ?? "",
                    input: block["input"] ?? .object([:])
                )
            default:
                return .opaque(vendor: Self.vendor, block)
            }
        }
        let stop: ModelResponse.StopReason
        switch json["stop_reason"]?.stringValue {
        case "end_turn", "stop_sequence": stop = .endTurn
        case "tool_use": stop = .toolUse
        case "max_tokens": stop = .maxTokens
        case "refusal": stop = .refusal
        case let other: stop = .other(other ?? "unknown")
        }
        return ModelResponse(blocks: blocks, stopReason: stop)
    }
}
