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
            // Active indicator bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? Color(nsColor: Colors.accentPrimary) : Color.clear)
                .frame(width: 3, height: 20)

            // Favicon
            faviconView

            // Title
            Text(tab.displayTitle)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected
                                 ? Color(nsColor: Colors.foregroundPrimary)
                                 : Color(nsColor: Colors.foregroundSecondary)
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color(nsColor: Colors.surfacePrimary)
                      : isHovered
                        ? Color(nsColor: Colors.surfacePrimary).opacity(0.4)
                        : Color.clear
                )
        )
        .padding(.horizontal, 6)
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
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else if let faviconURL = tab.faviconURL {
            AsyncImage(url: faviconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                default:
                    globePlaceholder
                }
            }
        } else {
            globePlaceholder
        }
    }

    private var globePlaceholder: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: Colors.borderLight).opacity(0.5))
            .frame(width: 16, height: 16)
            .overlay(
                Image(systemName: "globe")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            )
    }
}
