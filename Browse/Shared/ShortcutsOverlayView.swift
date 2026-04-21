import SwiftUI

struct ShortcutsOverlayView: View {
    let onClose: () -> Void

    // Lay out sections in a 2-column adaptive grid
    private let gridColumns = [
        GridItem(.flexible(), spacing: 20),
        GridItem(.flexible(), spacing: 20),
    ]

    var body: some View {
        ZStack {                    
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: Colors.chromeBg))
                .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 6)

            innerContent
                .padding(12)
        }
    }

    // MARK: - Inner content area (white card with rounded corners)

    private var innerContent: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 20) {
                ForEach(ShortcutsCatalog.sections) { section in
                    sectionView(section)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Color(nsColor: Colors.surfacePrimary))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Section

    private func sectionView(_ section: ShortcutSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
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
                .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(item.shortcut)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: Colors.surfaceSecondary))
                )
        }
    }
}
