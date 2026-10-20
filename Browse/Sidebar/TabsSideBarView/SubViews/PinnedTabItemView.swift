import SwiftUI

struct PinnedTabItemView: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onUnpin: () -> Void
    let onDuplicate: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        FaviconView(faviconURL: tab.faviconURL)
            .id(tab.faviconURL)
            .frame(width: 40, height: 40)
            .glassEffect(
                isSelected
                    ? .regular.tint(Color(nsColor: Colors.accentPrimary).opacity(0.25)).interactive()
                    : .regular.interactive(),
                in: shape
            )
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color(nsColor: Colors.accentPrimary).opacity(0.7), lineWidth: 1.5)
                }
            }
            .scaleEffect(isHovered ? 1.06 : 1.0)
            .animation(.smooth(duration: 0.15), value: isHovered)
            .contentShape(shape)
            .onTapGesture(perform: onSelect)
            .draggable(tab.id.uuidString)
            .contextMenu {
                Button("Unpin Tab", systemImage: "pin.slash", action: onUnpin)
                Divider()
                Button("Duplicate Tab", systemImage: "plus.square.on.square", action: onDuplicate)
            }
            .help(tab.displayTitle)
            .accessibilityLabel(tab.displayTitle)
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
