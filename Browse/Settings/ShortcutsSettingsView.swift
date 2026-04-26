import SwiftUI

/// Mirrors the visual layout of `ShortcutsOverlayView` (the ⌘/ cheat sheet)
/// so the Settings tab and the overlay look identical. Both views read from
/// `ShortcutsCatalog` — the single source of truth for shortcut bindings.
struct ShortcutsSettingsView: View {

    private let gridColumns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 20) {
                ForEach(ShortcutsCatalog.sections) { section in
                    sectionView(section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Section

    private func sectionView(_ section: ShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.accentPrimary))
                .tracking(0.5)

            VStack(spacing: 4) {
                ForEach(section.items) { item in
                    shortcutRow(item)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func shortcutRow(_ item: AppShortcut) -> some View {
        HStack(spacing: 8) {
            Text(item.action)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: NSColor(hex: "#142236")))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: Colors.surfacePrimary))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: Colors.accentPrimary).opacity(0.5))
                )
        }
    }
}
