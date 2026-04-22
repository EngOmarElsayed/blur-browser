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

    var body: some View {
        HStack(spacing: 10) {
            // Favicon
            FaviconView(faviconURL: tab.faviconURL)
                .id(tab.faviconURL)

            // Title
            Text(tab.displayTitle)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected
                                 ? Color(nsColor: Colors.accentPrimary)
                                 : Color(nsColor: Colors.foregroundSecondary)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button(action: onPin) {
                    Image(systemName: "pin")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? Color(nsColor: Colors.accentPrimary): Color(nsColor: Colors.foregroundMuted)
                        )
                        .rotationEffect(.degrees(45))
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }

            if isHovered || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(
                            isSelected ? Color(nsColor: Colors.accentPrimary): Color(nsColor: Colors.foregroundMuted)
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color(nsColor: Colors.surfacePrimary)
                      : isHovered
                        ? Color(nsColor: Colors.surfacePrimary).opacity(0.4)
                        : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isSelected
                        ? Color(nsColor: Colors.accentPrimary)
                    : .clear,
                    lineWidth: isSelected ? 1.5 : 0
                )
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .draggable(tab.id.uuidString)
        .contextMenu {
            Button("Pin Tab", action: onPin)
            Divider()
            Button("Close Tab", action: onClose)
            Button("Close Other Tabs", action: onCloseOthers)
            Divider()
            Button("Duplicate Tab", action: onDuplicate)
        }
    }
}
