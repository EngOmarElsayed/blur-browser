import Foundation
import OSLog
import WebKit

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Blur-Browser", category: "NativeMessaging")

/// Bridges `browser.runtime.sendNativeMessage` / `connectNative` to
/// Chrome-style native messaging hosts: a JSON manifest naming an executable
/// that speaks length-prefixed JSON over stdin/stdout.
///
/// Hosts are looked up in our own folder first, then Chrome's, so hosts that
/// other apps already registered for Chrome (1Password, Bitwarden, …) are
/// found without extra setup:
///   ~/Library/Application Support/Blur-Browser/NativeMessagingHosts/<name>.json
///   ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/<name>.json
///   /Library/Google/Chrome/NativeMessagingHosts/<name>.json
///
/// Like Chrome, a host only runs for extensions listed in its
/// `allowed_origins`. The origin is `chrome-extension://<id>/`, with the ID
/// derived from the manifest's `key`, so an unpacked copy of a Chrome
/// extension keeps the ID its host expects.
@MainActor
final class NativeMessagingBridge {
    private var connections: [ObjectIdentifier: NativeHostProcess] = [:]

    func sendMessage(_ message: Any, toHost name: String?, from context: WKWebExtensionContext, replyHandler: @escaping (Any?, Error?) -> Void) {
        let host: NativeHostProcess
        do {
            host = try launchHost(named: name, for: context)
        } catch {
            return replyHandler(nil, error)
        }
        // One-shot: first reply wins, then the host is stopped.
        var replied = false
        host.onMessage = { reply in
            guard !replied else { return }
            replied = true
            replyHandler(reply, nil)
            host.terminate()
        }
        host.onExit = { error in
            guard !replied else { return }
            replied = true
            replyHandler(nil, error ?? NativeMessagingError.hostExited)
        }
        host.send(message)
    }

    func connect(_ port: WKWebExtension.MessagePort, from context: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        let host: NativeHostProcess
        do {
            host = try launchHost(named: port.applicationIdentifier, for: context)
        } catch {
            return completionHandler(error)
        }
        let key = ObjectIdentifier(port)
        connections[key] = host

        let name = port.applicationIdentifier ?? "?"
        host.onMessage = { [weak port] message in
            logger.debug("\(name, privacy: .public) → extension: \(Self.typeSummary(message), privacy: .public)")
            port?.sendMessage(message) { _ in }
        }
        host.onExit = { [weak self, weak port] error in
            logger.notice("\(name, privacy: .public) exited\(error == nil ? "" : " with an error", privacy: .public)")
            self?.connections[key] = nil
            port?.disconnect(throwing: error)
        }
        port.messageHandler = { [weak host] message, _ in
            guard let message else { return }
            logger.debug("extension → \(name, privacy: .public): \(Self.typeSummary(message), privacy: .public)")
            host?.send(message)
        }
        port.disconnectHandler = { [weak self] _ in
            self?.connections.removeValue(forKey: key)?.terminate()
        }
        completionHandler(nil)
    }

    private func launchHost(named name: String?, for context: WKWebExtensionContext) throws -> NativeHostProcess {
        guard let name, !name.isEmpty else { throw NativeMessagingError.missingHostName }
        guard let manifest = Self.findManifest(named: name) else { throw NativeMessagingError.hostNotFound(name) }

        let origin: String
        if let chromeID = WebExtensionManager.chromeExtensionID(for: context.webExtension) {
            origin = "chrome-extension://\(chromeID)/"
        } else {
            origin = "webkit-extension://\(context.uniqueIdentifier)/"
        }
        guard manifest.allowedOrigins.contains(origin) else {
            logger.error("\(name, privacy: .public) refused: \(origin, privacy: .public) isn't in its allowed_origins")
            throw NativeMessagingError.originNotAllowed(name, origin)
        }
        logger.notice("Launching native host \(name, privacy: .public) (\(manifest.path.path, privacy: .public)) for \(origin, privacy: .public)")
        return try NativeHostProcess(executable: manifest.path, origin: origin)
    }

    /// The `type` fields of a message (nested up to a few levels), e.g.
    /// "NotificationModern/BrowserVerificationFailed". Logged instead of the
    /// message itself, which can hold secrets.
    nonisolated static func typeSummary(_ message: Any) -> String {
        var types: [String] = []
        func walk(_ value: Any, depth: Int) {
            guard depth < 4, let dict = value as? [String: Any] else { return }
            if let type = dict["type"] as? String { types.append(type) }
            // Status codes such as "UnknownBrowser" sit beside "type" as a bare string.
            if dict["type"] != nil, let code = dict["content"] as? String, code.count < 64 { types.append(code) }
            for key in ["invocation", "content", "data", "response"] {
                if let child = dict[key] { walk(child, depth: depth + 1) }
            }
        }
        walk(message, depth: 0)
        return types.isEmpty ? "(no type)" : types.joined(separator: "/")
    }

    struct HostManifest {
        let path: URL
        let allowedOrigins: [String]
    }

    static var searchDirectories: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/Blur-Browser/NativeMessagingHosts"),
            home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts"),
            URL(fileURLWithPath: "/Library/Google/Chrome/NativeMessagingHosts"),
        ]
    }

    static func findManifest(named name: String) -> HostManifest? {
        // Host names are restricted like Chrome's: lowercase alphanumerics, '.', '_'.
        guard name.allSatisfy({ $0.isLowercase || $0.isNumber || $0 == "." || $0 == "_" }) else { return nil }
        for directory in searchDirectories {
            let file = directory.appendingPathComponent("\(name).json")
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "stdio",
                  let path = json["path"] as? String else { continue }
            let executable = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
            return HostManifest(path: executable, allowedOrigins: json["allowed_origins"] as? [String] ?? [])
        }
        return nil
    }
}

enum NativeMessagingError: LocalizedError {
    case missingHostName
    case hostNotFound(String)
    case originNotAllowed(String, String)
    case hostExited

    var errorDescription: String? {
        switch self {
        case .missingHostName: "No native messaging host was named."
        case .hostNotFound(let name): "Native messaging host \(name) isn't installed."
        case .originNotAllowed(let name, let origin): "Native messaging host \(name) doesn't allow \(origin)."
        case .hostExited: "The native messaging host exited."
        }
    }
}

/// One running host process. Frames are a UInt32 length (native byte order)
/// followed by that many bytes of UTF-8 JSON, in both directions.
@MainActor
final class NativeHostProcess {
    var onMessage: ((Any) -> Void)?
    var onExit: ((Error?) -> Void)?

    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let reader = FrameReader()

    init(executable: URL, origin: String) throws {
        process.executableURL = executable
        // Chrome passes the caller's origin as the first argument.
        process.arguments = [origin]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let reader = reader
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for frame in reader.append(data) {
                guard let message = try? JSONSerialization.jsonObject(with: frame, options: .fragmentsAllowed) else { continue }
                nonisolated(unsafe) let sendable = message
                Task { @MainActor in self?.onMessage?(sendable) }
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in
                self?.stdout.fileHandleForReading.readabilityHandler = nil
                self?.onExit?(status == 0 ? nil : NativeMessagingError.hostExited)
                self?.onExit = nil
            }
        }
        try process.run()
    }

    func send(_ message: Any) {
        guard process.isRunning,
              let body = try? JSONSerialization.data(withJSONObject: message, options: .fragmentsAllowed) else { return }
        var length = UInt32(body.count)
        var frame = Data(bytes: &length, count: 4)
        frame.append(body)
        try? stdin.fileHandleForWriting.write(contentsOf: frame)
    }

    func terminate() {
        onExit = nil
        if process.isRunning { process.terminate() }
    }
}

/// Reassembles length-prefixed frames from stdout chunks. Called on the pipe's
/// background queue, so it guards its buffer with a lock.
private final class FrameReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self)) }
            guard buffer.count >= 4 + length else { break }
            frames.append(buffer.subdata(in: buffer.startIndex + 4 ..< buffer.startIndex + 4 + length))
            buffer.removeFirst(4 + length)
        }
        return frames
    }
}
