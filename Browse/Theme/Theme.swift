import AppKit

// MARK: - Theme ID

enum ThemeID: String, CaseIterable, Identifiable, Sendable, Codable {
    case periwinkle, midnight, sandstone, nordic, rosewood, verdant, graphite

    var id: String { rawValue }

    static var `default`: ThemeID { .periwinkle }
}

// MARK: - Theme

struct Theme: Sendable, Identifiable {
    let id: ThemeID
    let displayName: String
    let mood: String
    let chromeHex: String
    let foregroundHex: String
    let accentHex: String
    let borderHex: String
    let wallpaperNames: [String]
    let isDark: Bool

    var chromeColor: NSColor { NSColor(hex: chromeHex) }
    var foregroundColor: NSColor { NSColor(hex: foregroundHex) }
    var accentColor: NSColor { NSColor(hex: accentHex) }
    var borderColor: NSColor { NSColor(hex: borderHex) }

    /// Slightly-more-saturated version of the chrome color for active tab highlight backgrounds.
    /// Computed as a 15% blend with the accent color.
    var activeTabHighlight: NSColor {
        chromeColor.blended(withFraction: 0.15, of: accentColor) ?? accentColor
    }
}

// MARK: - Catalog

extension Theme {
    static let all: [Theme] = [
        Theme(
            id: .periwinkle,
            displayName: "Periwinkle",
            mood: "Airy sky blue through frosted glass",
            chromeHex: "#92B4F4",
            foregroundHex: "#1A1A1A",
            accentHex: "#6366F1",
            borderHex: "#C5CAE0",
            wallpaperNames: [
                "turquoise-lake-aerial-view",
                "lavender-bloom-macro-detail",
                "white-building-blue-sky",
                "pale-blue-pool-diagonal-shadow",
                "frosted-glass-blue-violet-light"
            ],
            isDark: false
        ),
        Theme(
            id: .midnight,
            displayName: "Midnight",
            mood: "Ink-blue darkness with a soft indigo glow",
            chromeHex: "#1C1E2A",
            foregroundHex: "#E2E4EA",
            accentHex: "#818CF8",
            borderHex: "#3A3D50",
            wallpaperNames: [
                "starry-night-mountain-silhouette",
                "city-grid-at-night-amber-lights",
                "volcanic-rock-blue-glow",
                "long-exposure-waves-dark-rocks",
                "ink-in-water-indigo-swirls"
            ],
            isDark: true
        ),
        Theme(
            id: .sandstone,
            displayName: "Sandstone",
            mood: "Sun-baked clay and natural linen",
            chromeHex: "#D4C4A8",
            foregroundHex: "#2C2416",
            accentHex: "#C2703E",
            borderHex: "#BFB093",
            wallpaperNames: [
                "sand-dunes-golden-hour",
                "terracotta-rooftops-warm-ochre",
                "raw-linen-fabric-soft-light",
                "desert-canyon-layered-sandstone",
                "ceramic-bowl-window-light"
            ],
            isDark: false
        ),
        Theme(
            id: .nordic,
            displayName: "Nordic",
            mood: "Scandinavian winter clarity, fjord-blue accents",
            chromeHex: "#C9D0DC",
            foregroundHex: "#1E2A33",
            accentHex: "#5B8FA8",
            borderHex: "#BCC4D1",
            wallpaperNames: [
                "fjord-overcast-light",
                "birch-forest-winter",
                "scandinavian-interior-pale-wood",
                "frozen-lake-ice-cracks",
                "coastal-rocks-lichen-calm-sea"
            ],
            isDark: false
        ),
        Theme(
            id: .rosewood,
            displayName: "Rosewood",
            mood: "Dusty rose with warm plum undertones",
            chromeHex: "#DCCDD2",
            foregroundHex: "#2D1F23",
            accentHex: "#A3586C",
            borderHex: "#C4B2B8",
            wallpaperNames: [
                "pampas-grass-pale-pink-wall",
                "pink-marble-veins-blush",
                "flat-lay-dried-flowers-linen",
                "cherry-blossoms-muted-sky",
                "rose-concrete-shadow-play"
            ],
            isDark: false
        ),
        Theme(
            id: .verdant,
            displayName: "Verdant",
            mood: "Botanical green, sunlit greenhouse",
            chromeHex: "#B4C4B0",
            foregroundHex: "#1A261A",
            accentHex: "#527C52",
            borderHex: "#A8B8A4",
            wallpaperNames: [
                "monstera-leaves-water-droplets",
                "misty-forest-path-soft-green",
                "terraced-rice-paddies-emerald",
                "moss-on-ancient-stone-rain",
                "greenhouse-climbing-plants"
            ],
            isDark: false
        ),
        Theme(
            id: .graphite,
            displayName: "Graphite",
            mood: "Neutral warm grays — invisible chrome",
            chromeHex: "#C8C8C8",
            foregroundHex: "#222222",
            accentHex: "#5A5A5A",
            borderHex: "#B5B5B5",
            wallpaperNames: [
                "brutalist-curves-concrete",
                "fog-over-mountain-ridge",
                "pencil-strokes-textured-paper",
                "pebble-beach-mist-gray-stones",
                "abstract-gray-geometric-shapes"
            ],
            isDark: false
        )
    ]

    static func theme(for id: ThemeID) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }
}
