import Foundation
import WebKit

/// Persists cookies across app launches by snapshotting WKWebView's cookie store
/// to UserDefaults on quit and restoring it on launch.
///
/// This works around the fact that session cookies (cookies without an explicit
/// expiration date — which includes many login session cookies) are cleared when
/// WKWebView's process ends. By archiving them and restoring on next launch, the
/// user stays logged in to sites that use session cookies.
@MainActor
enum CookieStore {

    private static let key = "persistedCookies"

    /// Snapshot all cookies from the shared WKWebsiteDataStore and write them to UserDefaults.
    static func save() async {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()

        let serializable: [[String: Any]] = cookies.compactMap { cookie -> [String: Any]? in
            guard let properties = cookie.properties else { return nil }
            var result: [String: Any] = [:]
            for (key, value) in properties {
                if let date = value as? Date {
                    result[key.rawValue] = ISO8601DateFormatter().string(from: date)
                } else {
                    result[key.rawValue] = value
                }
            }
            // Give session cookies (no expires / no max-age) an explicit
            // long-lived expiration so HTTPCookie(properties:) can reconstruct them.
            if result[HTTPCookiePropertyKey.expires.rawValue] == nil &&
               result[HTTPCookiePropertyKey.maximumAge.rawValue] == nil {
                let futureDate = Date().addingTimeInterval(60 * 60 * 24 * 30) // 30 days
                result[HTTPCookiePropertyKey.expires.rawValue] = ISO8601DateFormatter().string(from: futureDate)
            }
            return result
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: serializable, options: [])
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("[CookieStore] Failed to save cookies: \(error)")
        }
    }

    /// Restore previously saved cookies into the shared WKWebsiteDataStore.
    static func restore() async {
        guard let data = UserDefaults.standard.data(forKey: key),
              let serializable = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }

        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        let dateFormatter = ISO8601DateFormatter()

        for dict in serializable {
            var properties: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in dict {
                let cookieKey = HTTPCookiePropertyKey(rawValue: key)
                if cookieKey == .expires,
                   let str = value as? String,
                   let date = dateFormatter.date(from: str) {
                    properties[cookieKey] = date
                } else {
                    properties[cookieKey] = value
                }
            }
            if let cookie = HTTPCookie(properties: properties) {
                await cookieStore.setCookie(cookie)
            }
        }
    }
}
