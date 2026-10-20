import Foundation

/// Any `/v1/chat/completions` endpoint: OpenAI itself, and local servers
/// (llama.cpp, vLLM, LM Studio, Ollama) or the loopback relay in
/// `tools/relay.py`. Streams, and does function calling when the config
/// allows it.
struct OpenAICompatibleProvider: ModelProvider {
    static let vendor = "openai"

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
        let base = Self.normalizeBase(config.baseURL, fallback: config.kind.defaultBaseURL)
        guard let url = URL(string: base + "/chat/completions") else {
            throw ModelProviderError.badURL(config.baseURL)
        }

        var body: [String: JSONValue] = [
            "model": .string(config.model),
            "messages": .array(Self.encode(system: system, messages: messages, flattenTools: tools.isEmpty)),
            "stream": .bool(true),
        ]
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { tool in
                .object([
                    "type": .string("function"),
                    "function": .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "parameters": tool.inputSchema,
                    ]),
                ])
            })
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))

        var text = ""
        var splitter = ThinkTagSplitter()
        var calls: [Int: (id: String, name: String, arguments: String)] = [:]
        var finishReason: String?
        do {
            for try await chunk in ProviderHTTP.streamJSON(request) {
                if let message = chunk["error"]?["message"]?.stringValue {
                    throw ModelProviderError.http(status: 0, message: message)
                }
                guard let choice = chunk["choices"]?[0] else { continue }
                if let reason = choice["finish_reason"]?.stringValue { finishReason = reason }
                guard let delta = choice["delta"] else { continue }

                if let content = delta["content"]?.stringValue, !content.isEmpty {
                    // Reasoning models served raw put their scratchpad in <think> tags.
                    let closedBefore = splitter.sawUnopenedClose
                    let pieces = splitter.feed(content)
                    // Text so far was really reasoning (see ThinkTagSplitter).
                    if !closedBefore && splitter.sawUnopenedClose { text = "" }
                    for piece in pieces {
                        if piece.isReasoning {
                            await onEvent(.reasoning(piece.text))
                        } else {
                            text += piece.text
                            await onEvent(.text(piece.text))
                        }
                    }
                }
                if let reasoning = (delta["reasoning_content"] ?? delta["reasoning"])?.stringValue, !reasoning.isEmpty {
                    await onEvent(.reasoning(reasoning))
                }
                for call in delta["tool_calls"]?.arrayValue ?? [] {
                    let index = call["index"]?.intValue ?? 0
                    var entry = calls[index] ?? (id: "", name: "", arguments: "")
                    if let id = call["id"]?.stringValue, !id.isEmpty { entry.id = id }
                    if let name = call["function"]?["name"]?.stringValue { entry.name += name }
                    if let args = call["function"]?["arguments"]?.stringValue { entry.arguments += args }
                    calls[index] = entry
                }
            }
        } catch {
            throw ProviderHTTP.describe(error, baseURL: config.baseURL)
        }
        if let rest = splitter.flush(), !rest.isReasoning { text += rest.text }

        var blocks: [AgentContentBlock] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { blocks.append(.text(trimmed)) }
        for index in calls.keys.sorted() {
            guard let call = calls[index], !call.name.isEmpty else { continue }
            let args = call.arguments.trimmingCharacters(in: .whitespacesAndNewlines)
            let input = (try? JSONDecoder().decode(JSONValue.self, from: Data((args.isEmpty ? "{}" : args).utf8)))
                ?? .object([:])
            blocks.append(.toolUse(id: call.id.isEmpty ? "call_\(UUID().uuidString)" : call.id, name: call.name, input: input))
        }

        let hasToolUse = blocks.contains { if case .toolUse = $0 { true } else { false } }
        let stop: ModelResponse.StopReason
        switch finishReason {
        case _ where hasToolUse && finishReason != "length": stop = .toolUse
        case "length": stop = .maxTokens
        case "content_filter": stop = .refusal
        case "stop", nil: stop = .endTurn
        case let other: stop = .other(other ?? "unknown")
        }
        return ModelResponse(blocks: blocks, stopReason: stop)
    }

    // MARK: - Wire format

    /// When no tools are offered (chat-only endpoint), earlier tool calls in
    /// the history are written out as text, since many servers reject
    /// `tool_calls` in a request without `tools`.
    private static func encode(system: String, messages: [AgentMessage], flattenTools: Bool) -> [JSONValue] {
        var out: [JSONValue] = [.object(["role": .string("system"), "content": .string(system)])]
        for message in messages {
            switch message.role {
            case .assistant:
                var text: [String] = []
                var calls: [JSONValue] = []
                for block in message.blocks {
                    switch block {
                    case .text(let t): text.append(t)
                    case .toolUse(let id, let name, let input):
                        if flattenTools {
                            text.append("[Called \(name) \(input.compactDescription)]")
                        } else {
                            calls.append(.object([
                                "id": .string(id),
                                "type": .string("function"),
                                "function": .object([
                                    "name": .string(name),
                                    "arguments": .string(input.compactDescription),
                                ]),
                            ]))
                        }
                    case .toolResult, .opaque: break
                    }
                }
                let joined = text.joined(separator: "\n\n")
                var entry: [String: JSONValue] = ["role": .string("assistant")]
                entry["content"] = joined.isEmpty && !calls.isEmpty ? .null : .string(joined)
                if !calls.isEmpty { entry["tool_calls"] = .array(calls) }
                out.append(.object(entry))

            case .user:
                var text: [String] = []
                for block in message.blocks {
                    switch block {
                    case .text(let t): text.append(t)
                    case .toolResult(let id, let content, let isError):
                        let body = isError ? "Error: \(content)" : content
                        if flattenTools {
                            text.append("[Tool result]\n\(body)")
                        } else {
                            // Tool messages must directly follow the assistant turn.
                            out.append(.object([
                                "role": .string("tool"),
                                "tool_call_id": .string(id),
                                "content": .string(body),
                            ]))
                        }
                    case .toolUse, .opaque: break
                    }
                }
                if !text.isEmpty {
                    out.append(.object(["role": .string("user"), "content": .string(text.joined(separator: "\n\n"))]))
                }
            }
        }
        return out
    }

    /// Trims whitespace, trailing slashes and a pasted endpoint path, so
    /// `…/v1`, `…/v1/` and `…/v1/chat/completions` all work.
    static func normalizeBase(_ raw: String, fallback: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        for suffix in ["/chat/completions", "/messages", "/models"] where value.hasSuffix(suffix) {
            value.removeLast(suffix.count)
        }
        return value.isEmpty ? fallback : value
    }
}

/// Splits streamed text into answer and `<think>…</think>` reasoning, across
/// chunk boundaries. Some chat templates open the think block in the prompt,
/// so the output starts mid-reasoning and only has the closing tag; then
/// `sawUnopenedClose` is set and everything before it was reasoning.
struct ThinkTagSplitter {
    private var inThink = false
    private var pending = ""
    private var seenTag = false
    private(set) var sawUnopenedClose = false

    mutating func feed(_ chunk: String) -> [(isReasoning: Bool, text: String)] {
        var out: [(Bool, String)] = []
        var buffer = pending + chunk
        pending = ""
        while !buffer.isEmpty {
            let open = inThink ? nil : buffer.range(of: "<think>")
            let close = buffer.range(of: "</think>")
            if !inThink, !seenTag, let close, open.map({ close.lowerBound < $0.lowerBound }) ?? true {
                let before = String(buffer[..<close.lowerBound])
                if !before.isEmpty { out.append((true, before)) }
                sawUnopenedClose = true
                seenTag = true
                buffer = String(buffer[close.upperBound...])
            } else if let range = inThink ? close : open {
                let before = String(buffer[..<range.lowerBound])
                if !before.isEmpty { out.append((inThink, before)) }
                inThink.toggle()
                seenTag = true
                buffer = String(buffer[range.upperBound...])
            } else {
                // Hold back a possible partial tag at the end of the chunk.
                let tags = inThink || seenTag ? [inThink ? "</think>" : "<think>"] : ["<think>", "</think>"]
                let keep = tags.compactMap { tag in
                    (1..<tag.count).reversed().first { buffer.hasSuffix(tag.prefix($0)) }
                }.max() ?? 0
                let emit = String(buffer.dropLast(keep))
                if !emit.isEmpty { out.append((inThink, emit)) }
                pending = String(buffer.suffix(keep))
                buffer = ""
            }
        }
        return out
    }

    /// Whatever was held back as a possible tag, at end of stream.
    mutating func flush() -> (isReasoning: Bool, text: String)? {
        defer { pending = "" }
        return pending.isEmpty ? nil : (inThink, pending)
    }
}
