import Foundation

// MARK: - JSON value

/// A JSON value the agent can pass between the model and its tools without
/// committing to a concrete Codable type for every tool input.
enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case .number(let n): return Int(n)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Compact JSON for display in approval cards and logs.
    var compactDescription: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Provider-neutral transcript

/// One block of a turn. `opaque` carries provider-specific data (Claude
/// `thinking` blocks, Gemini parts with thought signatures) that must be echoed
/// back unchanged on the next request. `vendor` names the wire format it came
/// from; other providers skip it, so switching models mid-conversation works.
enum AgentContentBlock: Sendable, Equatable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseID: String, content: String, isError: Bool)
    case opaque(vendor: String, JSONValue)
}

struct AgentMessage: Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    var blocks: [AgentContentBlock]
}

/// Tool definition handed to the model: name, description, JSON Schema.
struct ModelToolDefinition: Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
}

struct ModelResponse: Sendable {
    enum StopReason: Sendable, Equatable {
        case endTurn, toolUse, maxTokens, refusal, other(String)
    }
    let blocks: [AgentContentBlock]
    let stopReason: StopReason
}

/// Streamed output shown while a response is still arriving. The final
/// `ModelResponse` is what's kept; these are for display only.
enum ModelStreamEvent: Sendable {
    case text(String)
    case reasoning(String)
}

enum ModelProviderError: LocalizedError {
    case missingAPIKey
    case badURL(String)
    case http(status: Int, message: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Add one in Settings → AI."
        case .badURL(let value):
            return "Invalid base URL: \(value)"
        case .http(let status, let message):
            return "The model request failed (\(status)): \(message)"
        case .decoding(let detail):
            return "Couldn't read the model response: \(detail)"
        }
    }
}

/// A chat model that can call tools. Implementations own the wire format; the
/// agent loop only sees `AgentMessage`s. Add new backends by conforming here.
protocol ModelProvider: Sendable {
    var displayName: String { get }
    /// False for endpoints that can't do tool calls (many local servers). The
    /// agent then runs as plain chat and attaches the page text itself.
    var supportsTools: Bool { get }
    /// `onEvent` receives text and reasoning as it streams, for providers that
    /// stream; others may never call it.
    func respond(
        system: String,
        messages: [AgentMessage],
        tools: [ModelToolDefinition],
        onEvent: @escaping @Sendable (ModelStreamEvent) async -> Void
    ) async throws -> ModelResponse
}

extension ModelProvider {
    var supportsTools: Bool { true }
}

// MARK: - Shared HTTP helpers

enum ProviderHTTP {
    /// POSTs `body` and returns the decoded JSON, mapping non-2xx to `.http`.
    static func postJSON(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        guard (200..<300).contains(status) else {
            throw ModelProviderError.http(status: status, message: errorMessage(json, raw: data))
        }
        guard let json else {
            throw ModelProviderError.decoding(String(decoding: data.prefix(300), as: UTF8.self))
        }
        return json
    }

    /// Server-sent events, one JSON object per `data:` line. `[DONE]` ends the
    /// stream. `AsyncBytes.lines` drops blank lines, so events can't be split on
    /// them — every provider here sends a complete object per data line.
    static func streamJSON(_ request: URLRequest) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var raw = ""
                        for try await line in bytes.lines {
                            raw += line
                            if raw.count > 2000 { break }
                        }
                        let json = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8))
                        throw ModelProviderError.http(status: status, message: errorMessage(json, raw: Data(raw.utf8)))
                    }
                    for try await rawLine in bytes.lines {
                        var line = Substring(rawLine)
                        if line.hasSuffix("\r") { line = line.dropLast() }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        if let json = try? JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8)) {
                            continuation.yield(json)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Turns a failed request into something readable. Network errors to a
    /// local server name the host, since macOS Local Network privacy is the
    /// usual cause (see docs/ai-agent.md, "Local models").
    static func describe(_ error: Error, baseURL: String) -> Error {
        guard let urlError = error as? URLError, urlError.code != .cancelled else { return error }
        return ModelProviderError.http(
            status: urlError.errorCode,
            message: "\(urlError.localizedDescription) — \(baseURL)")
    }

    private static func errorMessage(_ json: JSONValue?, raw: Data) -> String {
        if let message = json?["error"]?["message"]?.stringValue ?? json?["error"]?.stringValue
            ?? json?[0]?["error"]?["message"]?.stringValue {
            return message
        }
        let text = String(decoding: raw.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Unknown error" : text
    }
}
