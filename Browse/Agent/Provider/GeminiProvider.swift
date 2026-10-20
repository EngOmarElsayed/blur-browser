import Foundation

/// Google Gemini via `models/{model}:streamGenerateContent` (SSE), with
/// function calling.
///
/// Gemini attaches thought signatures to the parts it returns and expects the
/// model turn echoed back intact, so the raw `content` is kept as an opaque
/// block and sent back verbatim; the parsed text and function calls next to
/// it are what the agent loop reads.
struct GeminiProvider: ModelProvider {
    static let vendor = "gemini"

    let config: AIProviderConfig
    private let apiKey: String?

    init(config: AIProviderConfig, apiKey: String?) {
        self.config = config
        self.apiKey = apiKey
    }

    var displayName: String { "\(config.label) (\(config.model))" }
    var supportsTools: Bool { config.supportsTools }

    func respond(
        system: String,
        messages: [AgentMessage],
        tools: [ModelToolDefinition],
        onEvent: @escaping @Sendable (ModelStreamEvent) async -> Void
    ) async throws -> ModelResponse {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if key.isEmpty && !config.isLocal { throw ModelProviderError.missingAPIKey }
        let base = OpenAICompatibleProvider.normalizeBase(config.baseURL, fallback: config.kind.defaultBaseURL)
        guard var components = URLComponents(string: base + "/models/\(config.model):streamGenerateContent") else {
            throw ModelProviderError.badURL(config.baseURL)
        }
        components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
        guard let url = components.url else { throw ModelProviderError.badURL(config.baseURL) }

        var body: [String: JSONValue] = [
            "contents": .array(Self.encode(messages, flattenTools: tools.isEmpty)),
            "systemInstruction": .object(["parts": .array([.object(["text": .string(system)])])]),
        ]
        if !tools.isEmpty {
            body["tools"] = .array([.object([
                "functionDeclarations": .array(tools.map { tool in
                    var declaration: [String: JSONValue] = [
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                    ]
                    if let parameters = Self.geminiSchema(tool.inputSchema) {
                        declaration["parameters"] = parameters
                    }
                    return .object(declaration)
                }),
            ])])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "x-goog-api-key") }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        var rawParts: [JSONValue] = []
        var text = ""
        var calls: [AgentContentBlock] = []
        var finishReason: String?
        var blocked = false
        do {
            for try await chunk in ProviderHTTP.streamJSON(request) {
                if chunk["promptFeedback"]?["blockReason"] != nil { blocked = true }
                guard let candidate = chunk["candidates"]?[0] else { continue }
                if let reason = candidate["finishReason"]?.stringValue { finishReason = reason }
                for part in candidate["content"]?["parts"]?.arrayValue ?? [] {
                    rawParts.append(part)
                    if let call = part["functionCall"] {
                        calls.append(.toolUse(
                            id: call["id"]?.stringValue ?? "gemini-\(UUID().uuidString)",
                            name: call["name"]?.stringValue ?? "",
                            input: call["args"] ?? .object([:])))
                    } else if let chunkText = part["text"]?.stringValue, !chunkText.isEmpty {
                        if part["thought"]?.boolValue == true {
                            await onEvent(.reasoning(chunkText))
                        } else {
                            text += chunkText
                            await onEvent(.text(chunkText))
                        }
                    }
                }
            }
        } catch {
            throw ProviderHTTP.describe(error, baseURL: config.baseURL)
        }

        var blocks: [AgentContentBlock] = []
        if !rawParts.isEmpty {
            blocks.append(.opaque(vendor: Self.vendor, .object(["role": .string("model"), "parts": .array(rawParts)])))
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { blocks.append(.text(trimmed)) }
        blocks.append(contentsOf: calls)

        let stop: ModelResponse.StopReason
        switch finishReason {
        case _ where blocked: stop = .refusal
        case "MAX_TOKENS": stop = .maxTokens
        case _ where !calls.isEmpty: stop = .toolUse
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION": stop = .refusal
        case "STOP", nil: stop = .endTurn
        case let other: stop = .other(other ?? "unknown")
        }
        return ModelResponse(blocks: blocks, stopReason: stop)
    }

    // MARK: - Wire format

    private static func encode(_ messages: [AgentMessage], flattenTools: Bool) -> [JSONValue] {
        // functionResponse needs the function name; results only carry the id.
        var names: [String: String] = [:]
        for message in messages {
            for case .toolUse(let id, let name, _) in message.blocks { names[id] = name }
        }

        var out: [JSONValue] = []
        for message in messages {
            var parts: [JSONValue] = []
            switch message.role {
            case .assistant:
                let raw = message.blocks.lazy.compactMap { block -> JSONValue? in
                    if case .opaque(let vendor, let value) = block, vendor == Self.vendor { return value }
                    return nil
                }.first
                if let raw, !flattenTools {
                    out.append(raw)
                    continue
                }
                for block in message.blocks {
                    switch block {
                    case .text(let t):
                        parts.append(.object(["text": .string(t)]))
                    case .toolUse(_, let name, let input):
                        parts.append(flattenTools
                            ? .object(["text": .string("[Called \(name) \(input.compactDescription)]")])
                            : .object(["functionCall": .object(["name": .string(name), "args": input])]))
                    case .toolResult, .opaque: break
                    }
                }
                if !parts.isEmpty { out.append(.object(["role": .string("model"), "parts": .array(parts)])) }

            case .user:
                for block in message.blocks {
                    switch block {
                    case .text(let t):
                        parts.append(.object(["text": .string(t)]))
                    case .toolResult(let id, let content, let isError):
                        if flattenTools {
                            parts.append(.object(["text": .string("[Tool result]\n\(isError ? "Error: " : "")\(content)")]))
                        } else {
                            var response: [String: JSONValue] = [
                                "name": .string(names[id] ?? ""),
                                "response": .object([isError ? "error" : "output": .string(content)]),
                            ]
                            if !id.hasPrefix("gemini-") { response["id"] = .string(id) }
                            parts.append(.object(["functionResponse": .object(response)]))
                        }
                    case .toolUse, .opaque: break
                    }
                }
                if !parts.isEmpty { out.append(.object(["role": .string("user"), "parts": .array(parts)])) }
            }
        }
        return out
    }

    /// Gemini takes an OpenAPI subset: no `additionalProperties`, and an
    /// object schema with no properties must be left out entirely.
    private static func geminiSchema(_ schema: JSONValue) -> JSONValue? {
        guard case .object(var object) = schema else { return schema }
        object.removeValue(forKey: "additionalProperties")
        if case .array(let required)? = object["required"], required.isEmpty {
            object.removeValue(forKey: "required")
        }
        if case .object(let properties)? = object["properties"] {
            if properties.isEmpty { return nil }
            object["properties"] = .object(properties.compactMapValues(geminiSchema))
        }
        if let items = object["items"] { object["items"] = geminiSchema(items) }
        return .object(object)
    }
}
