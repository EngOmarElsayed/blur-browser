import SwiftUI

struct AutofillPopoverView: View {
    let credentials: [Credential]
    @Binding var selectedIndex: Int
    let onSelect: (Credential) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(credentials.enumerated()), id: \.element.id) { idx, cred in
                            row(for: cred, isSelected: idx == selectedIndex)
                                .id(cred.id)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(cred) }
                                .onHover { inside in if inside { selectedIndex = idx } }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, new in
                    if credentials.indices.contains(new) {
                        proxy.scrollTo(credentials[new].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 280)
        .background(Color(nsColor: Colors.surfacePrimary))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: Colors.accentPrimary), lineWidth: 1)
        )
    }

    private func row(for cred: Credential, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            if isSelected {
                Image(systemName: "touchid")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color(nsColor: Colors.accentPrimary))
                    .frame(width: 20, height: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cred.username)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: Colors.onSurfacePrimary))
                    .lineLimit(1)

                Text(cred.site)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Colors.onSurfaceSecondary))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color(nsColor: Colors.hoverBg) : Color.clear)
    }

    private func initial(_ s: String) -> String {
        String(s.first ?? "?").uppercased()
    }
}
