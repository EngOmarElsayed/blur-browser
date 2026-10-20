import AppKit
import WebKit

/// Receives `navigator.credentials` calls from `securityKeyShim.js` and runs
/// them against a USB security key. The origin always comes from the
/// message's `WKFrameInfo`, so a page can't claim to be another site.
@MainActor
final class SecurityKeyBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let handlerName = "blurSecurityKey"

    /// JSON-shaped dictionaries built and read on the main actor only.
    private struct Reply: @unchecked Sendable {
        let json: [String: Any]
    }

    private struct Active {
        let id: String
        let task: Task<Reply, Error>
        let request: SecurityKeyRequest
        weak var window: NSWindow?
    }

    private static var active: [String: Active] = [:]
    private static var abortedIDs: Set<String> = []

    static func install(in configuration: WKWebViewConfiguration) {
        guard let url = Bundle.main.url(forResource: "securityKeyShim", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            securityKeyLogger.error("securityKeyShim.js is not bundled; security keys unavailable")
            return
        }
        let ucc = configuration.userContentController
        ucc.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        ucc.addScriptMessageHandler(SecurityKeyBridge(), contentWorld: .page, name: handlerName)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any],
              let op = body["op"] as? String,
              let id = body["id"] as? String else {
            return (nil, "bad message")
        }
        switch op {
        case "cancel":
            Self.abortedIDs.insert(id)
            Self.cancel(id)
            return (nil, nil)
        case "create", "get":
            do {
                let result = try await perform(op: op, id: id, body: body, message: message)
                return (["ok": result], nil)
            } catch {
                let pageError = Self.pageError(for: error, id: id)
                securityKeyLogger.notice("WebAuthn \(op, privacy: .public) failed: \(pageError.name, privacy: .public) (\(String(describing: error), privacy: .public))")
                return (["error": ["name": pageError.name, "message": pageError.message]], nil)
            }
        default:
            return (nil, "unknown op")
        }
    }

    private func perform(op: String, id: String, body: [String: Any], message: WKScriptMessage) async throws -> [String: Any] {
        guard let webView = message.webView, let window = webView.window else {
            throw WebAuthnError.notAllowed("The page isn't visible.")
        }
        let frame = message.frameInfo
        let origin = WebOrigin(frame.securityOrigin)
        try origin.validateForWebAuthn()

        var topOrigin: WebOrigin?
        if !frame.isMainFrame {
            guard let top = WebOrigin(url: webView.url) else { throw WebAuthnError.notAllowed() }
            if top != origin {
                // We can't read the iframe's permissions policy, so only allow
                // sign-in (not registration) from a cross-origin frame.
                guard op == "get" else {
                    throw WebAuthnError.notAllowed("Creating credentials from a cross-origin frame isn't supported.")
                }
                topOrigin = top
            }
        }

        let options = body["options"] as? [String: Any] ?? [:]
        let activation = body["activation"] as? Bool ?? false
        let creation = op == "create" ? try CreationOptions(options) : nil
        let requestOptions = op == "get" ? try RequestOptions(options) : nil
        let timeout = creation?.timeout ?? requestOptions?.timeout ?? 300

        // One request per window: a new one replaces the last.
        for (otherID, other) in Self.active where other.window === window {
            Self.cancel(otherID)
        }

        let request = SecurityKeyRequest(origin: origin, topOrigin: topOrigin)
        let task = Task { @MainActor () throws -> Reply in
            do {
                if let creation {
                    return Reply(json: try await request.create(creation, hasUserActivation: activation))
                }
                return Reply(json: try await request.get(requestOptions!, hasUserActivation: activation))
            } catch let failure as SecurityKeyFailure {
                if !Task.isCancelled { await request.sheet.showFailure(failure.title, failure.message) }
                throw failure
            }
            catch let error where request.usingPhone && !Task.isCancelled
                        && !(error is WebAuthnError) && !(error is CancellationError) {
                // The phone closes the tunnel when the user cancels there or it
                // has no passkey for the site.
                await request.sheet.showFailure("Your phone ended the request",
                                                "If you didn't cancel on the phone, it may not have a passkey for this site.")
                throw error
            }
        }
        Self.active[id] = Active(id: id, task: task, request: request, window: window)
        request.sheet.onCancel = { Self.cancel(id) }
        request.sheet.present(on: window)

        var timedOut = false
        let timer = Task { @MainActor in
            try await Task.sleep(for: .seconds(timeout))
            timedOut = true
            Self.cancel(id)
        }
        defer {
            timer.cancel()
            request.finish()
            Self.active[id] = nil
            Self.abortedIDs.remove(id)
        }
        do {
            return try await task.value.json
        } catch {
            // A cancelled tunnel or HID read can surface as an I/O error.
            guard task.isCancelled else { throw error }
            if timedOut { throw WebAuthnError.notAllowed("The operation timed out.") }
            throw CancellationError()
        }
    }

    private static func cancel(_ id: String) {
        guard let active = active[id] else { return }
        active.task.cancel()
        // Unblocks a sheet waiting on PIN or account choice; the key itself
        // stops through CTAPHID_CANCEL.
        active.request.sheet.dismiss()
    }

    private static func pageError(for error: Error, id: String) -> WebAuthnError {
        switch error {
        case let error as WebAuthnError: return error
        case let failure as SecurityKeyFailure: return failure.pageError
        case is CancellationError where abortedIDs.contains(id):
            return WebAuthnError(name: "AbortError", message: "The operation was aborted.")
        default: return .notAllowed()
        }
    }
}
