import SwiftUI

struct TabItemView: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onPin: () -> Void
    let onDuplicate: () -> Void
    let onCloseOthers: () -> Void

    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        HStack(spacing: 10) {
            // Favicon
            FaviconView(faviconURL: tab.faviconURL)
                .id(tab.faviconURL)

            // Title
            Text(tab.displayTitle)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Color(nsColor: isSelected ? Colors.foregroundPrimary : Colors.foregroundSecondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                rowButton(symbol: "pin", help: "Pin Tab", action: onPin)
                    .rotationEffect(.degrees(45))
            }

            if isHovered || isSelected {
                rowButton(symbol: "xmark", help: "Close Tab", action: onClose)
            }
        }
        .padding(.vertical, 7)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .background {
            if !isSelected && isHovered {
                shape.fill(Color(nsColor: Colors.foregroundPrimary).opacity(0.07))
            }
        }
        .glassEffect(isSelected ? .regular.interactive() : .identity, in: shape)
        .animation(.smooth(duration: 0.2), value: isSelected)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .draggable(tab.id.uuidString)
        .contextMenu {
            Button("Pin Tab", systemImage: "pin", action: onPin)
            Divider()
            Button("Close Tab", systemImage: "xmark", action: onClose)
            Button("Close Other Tabs", action: onCloseOthers)
            Divider()
            Button("Duplicate Tab", systemImage: "plus.square.on.square", action: onDuplicate)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func rowButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .frame(width: 20, height: 20)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
