import Foundation
import WebKit

/// A DOMException the shim rethrows in the page.
struct WebAuthnError: Error {
    let name: String
    let message: String

    static func notAllowed(_ message: String = "The operation either timed out or was not allowed.") -> WebAuthnError {
        WebAuthnError(name: "NotAllowedError", message: message)
    }
    static func security(_ message: String) -> WebAuthnError { WebAuthnError(name: "SecurityError", message: message) }
    static func notSupported(_ message: String) -> WebAuthnError { WebAuthnError(name: "NotSupportedError", message: message) }
    static func type(_ message: String) -> WebAuthnError { WebAuthnError(name: "TypeError", message: message) }
    static let invalidState = WebAuthnError(name: "InvalidStateError", message: "The authenticator was previously registered.")
}

/// The caller's origin, taken from WebKit's `WKFrameInfo`, never from the page.
struct WebOrigin: Equatable {
    let scheme: String
    let host: String
    let port: Int

    init(scheme: String, host: String, port: Int) {
        self.scheme = scheme.lowercased()
        self.host = host.lowercased()
        let defaultPort = self.scheme == "https" ? 443 : self.scheme == "http" ? 80 : 0
        self.port = port == defaultPort ? 0 : port
    }

    @MainActor
    init(_ securityOrigin: WKSecurityOrigin) {
        self.init(scheme: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port)
    }

    init?(url: URL?) {
        guard let url, let scheme = url.scheme, let host = url.host else { return nil }
        self.init(scheme: scheme, host: host, port: url.port ?? 0)
    }

    /// RFC 6454 serialization, as clientDataJSON wants it.
    var serialized: String {
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return port == 0 ? "\(scheme)://\(hostPart)" : "\(scheme)://\(hostPart):\(port)"
    }

    var isLocalhost: Bool { host == "localhost" || host.hasSuffix(".localhost") }

    var isIPAddress: Bool {
        host.contains(":") || host.split(separator: ".").allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// WebAuthn needs a secure context whose host is a domain (§5.1.3 step 7).
    func validateForWebAuthn() throws {
        guard scheme == "https" || (scheme == "http" && isLocalhost) else {
            throw WebAuthnError.security("Security keys need a secure (HTTPS) page.")
        }
        guard !host.isEmpty, !isIPAddress else {
            throw WebAuthnError.security("Security keys can't be used on an IP address.")
        }
    }

    /// rpId must equal the origin's host or be a registrable suffix of it.
    func validateRPID(_ rpId: String) throws {
        let rpId = rpId.lowercased()
        let matches = host == rpId || host.hasSuffix("." + rpId)
        let registrable = rpId == "localhost" || (rpId.contains(".") && !PublicSuffix.isPublicSuffix(rpId))
        guard matches, registrable, !rpId.hasPrefix("."), !rpId.hasSuffix(".") else {
            throw WebAuthnError.security("The relying party ID is not a registrable domain suffix of, nor equal to the current domain.")
        }
    }

    /// FIDO AppID check as Chrome does it: the appid URL must be HTTPS on the
    /// same site, plus Google's well-known gstatic facet list.
    func validateAppID(_ appid: String) throws -> String {
        guard let url = URL(string: appid), url.scheme?.lowercased() == "https", let appHost = url.host?.lowercased() else {
            throw WebAuthnError.security("The appid extension is not a valid HTTPS URL.")
        }
        let isGoogle = host == "google.com" || host.hasSuffix(".google.com")
        if isGoogle, appHost == "www.gstatic.com", url.path.hasPrefix("/securitykey/") {
            return appid
        }
        guard PublicSuffix.registrableDomain(appHost) == PublicSuffix.registrableDomain(host) else {
            throw WebAuthnError.security("The appid extension is not allowed for this origin.")
        }
        return appid
    }
}

/// Builds clientDataJSON in the exact layout §5.8.1.1 specifies, so servers
/// that compare prefixes byte for byte accept it.
enum ClientData {
    static func json(type: String, challenge: Data, origin: WebOrigin, topOrigin: WebOrigin?) -> Data {
        var result = "{\"type\":" + quote(type)
        result += ",\"challenge\":" + quote(challenge.base64URLEncodedString())
        result += ",\"origin\":" + quote(origin.serialized)
        if let topOrigin {
            result += ",\"crossOrigin\":true,\"topOrigin\":" + quote(topOrigin.serialized)
        } else {
            result += ",\"crossOrigin\":false"
        }
        return Data((result + "}").utf8)
    }

    private static func quote(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case _ where scalar.value < 0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}

/// A small public suffix check. There's no public macOS API for the Public
/// Suffix List and no third-party code allowed here, so this covers every
/// single-label TLD plus the common multi-label and hosting suffixes. An
/// rpId outside this list but on the real PSL would be accepted; it still
/// has to be a suffix of the page's own host.
enum PublicSuffix {
    private static let multiLabel: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "net.uk", "ltd.uk", "plc.uk", "sch.uk", "nhs.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "id.au", "asn.au",
        "co.nz", "org.nz", "net.nz", "govt.nz", "ac.nz",
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp", "gr.jp",
        "co.kr", "or.kr", "go.kr", "ac.kr", "ne.kr",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn",
        "com.hk", "org.hk", "net.hk", "edu.hk", "gov.hk",
        "com.tw", "org.tw", "net.tw", "edu.tw", "gov.tw",
        "com.sg", "org.sg", "net.sg", "edu.sg", "gov.sg",
        "co.in", "net.in", "org.in", "firm.in", "gen.in", "ind.in", "ac.in", "gov.in",
        "com.br", "net.br", "org.br", "gov.br", "edu.br",
        "com.mx", "org.mx", "gob.mx", "edu.mx",
        "com.ar", "org.ar", "gob.ar",
        "com.tr", "org.tr", "gov.tr", "edu.tr",
        "co.za", "org.za", "gov.za", "ac.za",
        "com.pk", "org.pk", "gov.pk", "edu.pk",
        "co.il", "org.il", "ac.il", "gov.il",
        "com.my", "org.my", "gov.my", "edu.my",
        "co.id", "or.id", "go.id", "ac.id",
        "co.th", "or.th", "go.th", "ac.th",
        "com.vn", "com.ph", "com.eg", "com.sa", "com.ng", "co.ke", "com.ua", "com.pl", "com.es", "com.pt", "co.at", "or.at",
        "github.io", "gitlab.io", "githubusercontent.com", "herokuapp.com", "vercel.app", "netlify.app", "pages.dev",
        "workers.dev", "web.app", "firebaseapp.com", "appspot.com", "blogspot.com", "cloudfront.net",
        "azurewebsites.net", "azurestaticapps.net", "s3.amazonaws.com", "elasticbeanstalk.com", "ngrok.io",
        "ngrok-free.app", "ngrok.app", "glitch.me", "repl.co", "replit.dev", "fly.dev", "onrender.com",
        "surge.sh", "now.sh", "deno.dev", "railway.app", "bitbucket.io", "wixsite.com", "myshopify.com",
        "duckdns.org", "dyndns.org", "no-ip.org",
    ]

    static func isPublicSuffix(_ domain: String) -> Bool {
        !domain.contains(".") || multiLabel.contains(domain)
    }

    /// eTLD+1 under the same approximation.
    static func registrableDomain(_ host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        return multiLabel.contains(lastTwo) ? labels.suffix(3).joined(separator: ".") : lastTwo
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        self.init(base64Encoded: s)
    }
}
