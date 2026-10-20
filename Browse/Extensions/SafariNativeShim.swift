import AppKit
import CoreGraphics
import WebKit

/// Answers the few native messages 1Password for Safari sends to its own
/// Safari app-extension handler (`runtime.sendNativeMessage("", …)`).
///
/// That handler lives in "1Password for Safari.app" and only Safari can reach
/// it. Without answers, 1Password's Safari lock monitor treats the failed
/// `query-active-status` call as "locked" and relocks right after every
/// unlock, closing the popup ("[LM] Unable to communicate with native app,
/// locking."). We answer the stateless questions ourselves; everything that
/// needs 1Password's app (biometry, `core` device calls, in-app purchase)
/// still fails, and 1Password falls back to its account-password flow.
@MainActor
enum SafariNativeShim {
    static let supportedBundleIDs: Set<String> = ["com.1password.safari.extension"]

    enum ShimError: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self {
            case .unsupported(let name): "“\(name)” needs the extension's own Safari app."
            }
        }
    }

    static func reply(to message: Any) throws -> Any {
        guard let request = message as? [String: Any], let name = request["name"] as? String else {
            throw ShimError.unsupported("(unnamed)")
        }
        let data = (request["data"] as? String).flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        switch name {
        case "query-active-status":
            let maximumIdle = (data["maximumIdleTimeInSeconds"] as? NSNumber)?.doubleValue ?? .infinity
            return isUserActive(maximumIdleSeconds: maximumIdle) ? "active" : "locked"

        case "copy-to-clipboard":
            guard let value = data["value"] as? String else { throw ShimError.unsupported(name) }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(value, forType: .string)
            if (data["concealed"] as? Bool) == true {
                // Clipboard managers skip items marked concealed (nspasteboard.org).
                pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            }
            return true

        case "request-os-version":
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        default:
            throw ShimError.unsupported(name)
        }
    }

    /// The Mac counts as active when it has had input within `maximumIdleSeconds`
    /// and the screen isn't locked.
    static func isUserActive(maximumIdleSeconds: Double) -> Bool {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
           (session["CGSSessionScreenIsLocked"] as? Bool) == true {
            return false
        }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return idle < maximumIdleSeconds
    }

    /// Ports opened with `connectNative("")` carry lock notifications from
    /// the Safari app. We have none to send; keep the port open and quiet so
    /// the extension's lock monitor starts normally.
    private static var quietPorts: [ObjectIdentifier: WKWebExtension.MessagePort] = [:]

    static func acceptQuietPort(_ port: WKWebExtension.MessagePort) {
        let key = ObjectIdentifier(port)
        quietPorts[key] = port
        port.messageHandler = { [weak port] message, _ in
            if let message, let reply = try? SafariNativeShim.reply(to: message) {
                port?.sendMessage(reply) { _ in }
            }
        }
        port.disconnectHandler = { _ in
            SafariNativeShim.quietPorts[key] = nil
        }
    }
}
