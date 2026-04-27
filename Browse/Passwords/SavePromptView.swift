import SwiftUI

struct SavePromptView: View {
    enum Mode { case save, update }

    let mode: Mode
    let site: String
    @State var username: String
    @State var password: String
    @State private var revealPassword = false
    let onSubmit: (_ username: String, _ password: String) -> Void
    let onNever: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundStyle(Color(nsColor: Colors.onSurfacePrimary))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Colors.onSurfacePrimary))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(nsColor: Colors.onSurfaceMuted))
                }
                .buttonStyle(.plain)
            }
            if mode == .update {
                Text("This will replace your saved password for \(username).")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Colors.onSurfaceSecondary))
            }
            labelled("Username") {
                TextField("", text: $username).textFieldStyle(.roundedBorder)
            }
            labelled("Password") {
                HStack(spacing: 6) {
                    Group {
                        if revealPassword {
                            TextField("", text: $password)
                        } else {
                            SecureField("", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    Button {
                        revealPassword.toggle()
                    } label: {
                        Image(systemName: revealPassword ? "eye.slash" : "eye")
                            .foregroundStyle(Color(nsColor: Colors.onSurfaceMuted))
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button("Never for this site", action: onNever)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(nsColor: Colors.onSurfaceSecondary))
                Spacer()
                Button(primaryLabel) { onSubmit(username, password) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(Color(nsColor: Colors.surfacePrimary))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: Colors.borderLight), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: 8)
    }

    private var title: String {
        switch mode {
        case .save:   return "Save password for \(site)?"
        case .update: return "Update password for \(site)?"
        }
    }
    private var primaryLabel: String { mode == .save ? "Save" : "Update" }

    @ViewBuilder
    private func labelled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: Colors.onSurfaceSecondary))
            content()
        }
    }
}
