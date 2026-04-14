import SwiftUI

struct TabItemView: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onCloseOthers: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Blue active indicator bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? Color(nsColor: Colors.accentPrimary) : Color.clear)
                .frame(width: 3, height: 18)
            
            // Favicon
            faviconView
            
            // Title
            Text(tab.displayTitle)
                .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected
                                 ? Color(nsColor: Colors.foregroundPrimary)
                                 : Color(nsColor: Colors.foregroundSecondary)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if isHovered || isSelected {
                // Close button — always visible
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            isSelected
            ? Color(nsColor: Colors.surfacePrimary): Color.clear, in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal, 8)
//        .background(
//            isHovered && !isSelected
//                ? Color(nsColor: Colors.hoverBg).opacity(0.5)
//                : Color.clear
//        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("Close Tab", action: onClose)
            Button("Close Other Tabs", action: onCloseOthers)
            Divider()
            Button("Duplicate Tab", action: onDuplicate)
        }
    }

    @ViewBuilder
    private var faviconView: some View {
        if let image = tab.faviconImage {
            Image(nsImage: image)
                .resizable()
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: Colors.borderLight))
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                )
        }
    }
}
