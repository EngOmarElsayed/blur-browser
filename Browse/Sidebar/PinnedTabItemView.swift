import SwiftUI

struct PinnedTabItemView: View {
    let tab: BrowserTab
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onUnpin: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected
                      ? Color(nsColor: Colors.surfacePrimary)
                      : isHovered
                        ? Color(nsColor: Colors.surfacePrimary).opacity(0.5)
                        : Color(nsColor: Colors.surfacePrimary).opacity(0.25)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected
                                ? Color(nsColor: Colors.accentPrimary).opacity(0.6)
                                : Color(nsColor: Colors.borderLight).opacity(0.4),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )

            // Favicon or letter fallback
            faviconView
        }
        .frame(width: 35, height: 35)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .draggable(tab.id.uuidString)
        .contextMenu {
            Button("Unpin Tab", action: onUnpin)
            Divider()
            Button("Duplicate Tab", action: onDuplicate)
        }
        .help(tab.displayTitle)
    }

    // MARK: - Favicon

    @ViewBuilder
    private var faviconView: some View {
        if let image = tab.faviconImage {
            Image(nsImage: image)
                .resizable()
                .frame(width: 15, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let faviconURL = tab.faviconURL {
            AsyncImage(url: faviconURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .frame(width: 15, height: 15)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                default:
                    letterFallback
                }
            }
        } else {
            letterFallback
        }
    }

    private var letterFallback: some View {
        Text(domainInitial)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
    }

    private var domainInitial: String {
        let host = tab.url?.host ?? ""
        // Strip "www." prefix
        let clean = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return clean.first.map(String.init)?.uppercased() ?? "?"
    }
}
