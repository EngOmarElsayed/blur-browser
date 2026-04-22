import SwiftUI
import AppKit

// MARK: - Popover view (SwiftUI content)

struct ThemePickerPopoverView: View {
    @State private var themeStore = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Theme")
                .font(.custom(Typography.fontFamily, size: 11).weight(.semibold))
                .foregroundStyle(Color(nsColor: Colors.onSurfacePrimary))
                .textCase(.uppercase)

            HStack(spacing: 8) {
                ForEach(Theme.all) { theme in
                    swatch(theme)
                }
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    private func swatch(_ theme: Theme) -> some View {
        let isSelected = theme.id == themeStore.currentThemeID
        return Button {
            themeStore.select(theme.id)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(nsColor: theme.chromeColor))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(nsColor: theme.borderColor), lineWidth: 1)
                    )

                if isSelected {
                    Circle()
                        .strokeBorder(Color(nsColor: theme.accentColor), lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .help(theme.displayName)
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityHint(theme.mood)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - NSPopover host

@MainActor
final class ThemePickerPopoverController {

    static let shared = ThemePickerPopoverController()

    private let popover: NSPopover

    private init() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        let host = NSHostingController(rootView: ThemePickerPopoverView())
        popover.contentViewController = host
    }

    func show(relativeTo view: NSView) {
        if popover.isShown {
            popover.close()
            return
        }
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }
}
