import Foundation

/// Pure-function helper for normalizing URLs to a stable site key.
/// v1 implementation: naive last-two-labels eTLD+1.
/// FUTURE: replace with Public Suffix List lookup so foo.github.io != bar.github.io.
enum SiteIdentity {
    /// "https://mail.example.com/path" -> "example.com"
    /// Returns nil for IPs, localhost, and hosts with < 2 labels.
    static func site(for url: URL) -> String? {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host == "localhost" { return nil }
        if isIPAddress(host) { return nil }
        let labels = host.split(separator: ".")
        guard labels.count >= 2 else { return nil }
        return labels.suffix(2).joined(separator: ".")
    }

    /// Same as site(for:) but enforces save-eligibility rules:
    /// returns nil for non-https URLs (we never save credentials over HTTP).
    static func key(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" else { return nil }
        return site(for: url)
    }

    private static func isIPAddress(_ host: String) -> Bool {
        var sin = sockaddr_in()
        var sin6 = sockaddr_in6()
        if host.withCString({ inet_pton(AF_INET, $0, &sin.sin_addr) }) == 1 { return true }
        if host.withCString({ inet_pton(AF_INET6, $0, &sin6.sin6_addr) }) == 1 { return true }
        return false
    }
}
