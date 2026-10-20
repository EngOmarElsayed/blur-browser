import AppKit

// MARK: - Design Tokens (from Browser.pen)

enum Colors {
    // MARK: - Theme-aware tokens (resolve through ThemeStore)
    @MainActor static var foregroundPrimary: NSColor   { ThemeStore.shared.foregroundColor }
    // Secondary/muted alphas are tuned for legibility on the translucent glass
    // chrome — anything lower washes out over bright desktops.
    @MainActor static var foregroundSecondary: NSColor { ThemeStore.shared.foregroundColor.withAlphaComponent(0.82) }
    @MainActor static var foregroundMuted: NSColor     { ThemeStore.shared.foregroundColor.withAlphaComponent(0.68) }
    @MainActor static var accentPrimary: NSColor       { ThemeStore.shared.accentColor }
    @MainActor static var borderLight: NSColor         { ThemeStore.shared.borderColor }
    @MainActor static var hoverBg: NSColor             { ThemeStore.shared.accentColor.withAlphaComponent(0.12) }
    @MainActor static var sidebarBg: NSColor           { ThemeStore.shared.chromeColor }
    @MainActor static var chromeBg: NSColor            { ThemeStore.shared.chromeColor }
    /// Theme tint laid over the behind-window glass. Translucent so the desktop
    /// reads through, opaque enough that each theme keeps its identity.
    @MainActor static var chromeTint: NSColor          { ThemeStore.shared.chromeColor.withAlphaComponent(ThemeStore.shared.isDark ? 0.72 : 0.55) }

    // MARK: - Static (non-themed) tokens
    static let foregroundInverse = NSColor(hex: "#FFFFFF")
    static let surfaceInverse    = NSColor(hex: "#0A0A0A")
    /// Destructive / high-risk state (e.g. agent Dangerous mode).
    static let danger            = NSColor(hex: "#EF4444")

    // MARK: - Surfaces (appearance-aware)
    // Cards, popovers and settings panes. These resolve against the effective
    // appearance, which follows the theme (see ThemeStore.applyAppearance).
    static let surfacePrimary    = NSColor(name: "surfacePrimary") { appearance in
        appearance.isDark ? NSColor(hex: "#26272D") : NSColor(hex: "#FFFFFF")
    }
    static let surfaceSecondary  = NSColor(name: "surfaceSecondary") { appearance in
        appearance.isDark ? NSColor(hex: "#1E1F24") : NSColor(hex: "#F7F8FA")
    }

    // MARK: - Foreground on surfaces
    // Use these for text/icons drawn on surfacePrimary/surfaceSecondary
    // (popovers, cards, settings). System label colors keep contrast in both
    // light and dark appearances.
    static let onSurfacePrimary   = NSColor.labelColor
    static let onSurfaceSecondary = NSColor.secondaryLabelColor
    static let onSurfaceMuted     = NSColor.secondaryLabelColor
}

// MARK: - Layout Constants

enum Layout {
    static let sidebarDefaultWidth: CGFloat  = 220
    static let sidebarMinWidth: CGFloat      = 180
    static let sidebarMaxWidth: CGFloat      = 500
    static let toolbarHeight: CGFloat        = 52
    static let tabRowHeight: CGFloat         = 32
    static let urlBarHeight: CGFloat         = 36
    static let toolbarControlHeight: CGFloat = 34
    /// Inset between the window edge and the floating content card.
    static let chromeEdge: CGFloat           = 8
    /// Corner radius of the content card — concentric with the window corner
    /// across the `chromeEdge` gap.
    static let contentCornerRadius: CGFloat  = 14
    static let quickSearchWidth: CGFloat     = 650
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
    static let newTabURLString  = "blur://newtab"
    static let newTabURL        = URL(string: newTabURLString)!
    static let appName = "Blur-Browser"
}

// MARK: - Settings Colors (SwiftUI)

enum SettingsColors {
    // MARK: - Theme-aware tokens
    @MainActor static var chrome: Color       { Color(nsColor: ThemeStore.shared.chromeColor) }
    @MainActor static var windowBorder: Color { Color(nsColor: ThemeStore.shared.borderColor) }
    @MainActor static var borderLight: Color  { Color(nsColor: ThemeStore.shared.borderColor) }
    @MainActor static var accent: Color       { Color(nsColor: ThemeStore.shared.accentColor) }
    @MainActor static var fgPrimary: Color = Color(nsColor: Colors.onSurfacePrimary)
    @MainActor static var fgSecondary: Color = Color(nsColor: Colors.onSurfaceMuted)
    @MainActor static var hover: Color        { Color(nsColor: ThemeStore.shared.accentColor).opacity(0.12) }

    // MARK: - Static (non-themed)
    static let surface       = Color(nsColor: Colors.surfacePrimary)
    static let danger        = Color(hex: "#EF4444")
    static let allowGreen    = Color(hex: "#22C55E")
    static let denyRed       = Color(hex: "#EF4444")
    static let trafficRed    = Color(hex: "#FF5F57")
    static let trafficYellow = Color(hex: "#FEBC2E")
    static let trafficGreen  = Color(hex: "#28C840")
}

// MARK: - SwiftUI Color Hex Extension

import SwiftUI

extension Color {
    init(hex: String) {
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
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Appearance helpers

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua, .vibrantDark, .vibrantLight]).map {
            $0 == .darkAqua || $0 == .vibrantDark
        } ?? false
    }
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
