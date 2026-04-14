import AppKit

// MARK: - Design Tokens (from Browser.pen)

enum Colors {
    // Foreground
    static let foregroundPrimary   = NSColor(hex: "#1A1A1A")
    static let foregroundSecondary = NSColor(hex: "#666666")
    static let foregroundMuted     = NSColor(hex: "#888888")
    static let foregroundInverse   = NSColor(hex: "#FFFFFF")

    // Surfaces
    static let surfacePrimary   = NSColor(hex: "#FFFFFF")
    static let surfaceSecondary = NSColor(hex: "#F7F8FA")
    static let surfaceInverse   = NSColor(hex: "#0A0A0A")

    // UI
    static let accentPrimary = NSColor(hex: "#4A9FD8")
    static let borderLight   = NSColor(hex: "#E5E7EB")
    static let hoverBg       = NSColor(hex: "#EAECEF")
    static let sidebarBg     = NSColor(hex: "#F0F1F3")
}

// MARK: - Layout Constants

enum Layout {
    static let sidebarDefaultWidth: CGFloat  = 220
    static let sidebarMinWidth: CGFloat      = 180
    static let sidebarMaxWidth: CGFloat      = 500
    static let toolbarHeight: CGFloat        = 52
    static let tabRowHeight: CGFloat         = 32
    static let urlBarHeight: CGFloat         = 36
    static let quickSearchWidth: CGFloat     = 500
    static let quickSearchInputHeight: CGFloat = 48
    static let quickSearchResultHeight: CGFloat = 40
    static let findBarHeight: CGFloat        = 40
    static let historyHeaderHeight: CGFloat  = 48
    static let historyItemHeight: CGFloat    = 36
    static let faviconSize: CGFloat          = 16
    static let windowMinWidth: CGFloat       = 800
    static let windowMinHeight: CGFloat      = 600
}

// MARK: - Typography

enum Typography {
    static let fontFamily  = "Inter"
    static let monoFamily  = "Geist Mono"
    static let bodySize: CGFloat     = 13
    static let smallSize: CGFloat    = 12
    static let captionSize: CGFloat  = 11
    static let headingSize: CGFloat  = 14
    static let titleSize: CGFloat    = 24
}

// MARK: - App Constants

enum AppConstants {
    static let defaultSearchURL = "https://www.google.com/search?q="
    static let googleSuggestURL = "https://suggestqueries.google.com/complete/search?client=firefox&q="
    static let defaultHomeURL   = "https://www.google.com"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let appName = "Browse"
}

// MARK: - NSColor Hex Extension

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch hex.count {
        case 6:
            (r, g, b, a) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
