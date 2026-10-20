import SwiftUI

/// Shown in the agent pane instead of the chat while saved chats are locked.
struct AgentLockedView: View {
    let vault: AgentConversationVault

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                .frame(width: 56, height: 56)
                .glassEffect(.regular, in: Circle())
            Text("Saved chats are locked")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
            Text("Your agent chats are encrypted on this Mac. Unlock to see them and keep chatting.")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await vault.unlock() }
            } label: {
                Label(vault.state == .unlocking ? "Unlocking…" : "Unlock with Touch ID", systemImage: "touchid")
            }
            .buttonStyle(.glassProminent)
            .tint(SettingsColors.accent)
            .disabled(vault.state == .unlocking)
            if let error = vault.unlockError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsColors.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The header's list of saved chats: switch, rename, delete, lock.
struct AgentConversationsPopover: View {
    let controller: AgentController
    let vault: AgentConversationVault
    var onDone: () -> Void

    @State private var renamingID: UUID?
    @State private var renameDraft = ""
    @State private var confirmDeleteID: UUID?
    @State private var hoveredID: UUID?
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Saved Chats")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                Spacer()
                if AgentChatSettings.requireAuthentication {
                    Button {
                        onDone()
                        vault.lock()
                    } label: {
                        Label("Lock", systemImage: "lock")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Lock saved chats now")
                }
                Button {
                    controller.resetConversation()
                    onDone()
                } label: {
                    Label("New", systemImage: "square.and.pencil")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(controller.isRunning)
            }
            .padding(12)

            if vault.summaries.isEmpty {
                Text("No saved chats yet. Chats are saved, encrypted, as you go.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.horizontal, .bottom], 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(vault.summaries) { summary in
                            row(summary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 360)
            }

            if vault.unreadableCount > 0 {
                Text("\(vault.unreadableCount) saved chat\(vault.unreadableCount == 1 ? "" : "s") can't be opened with this Mac's key.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    .padding([.horizontal, .bottom], 12)
            }
        }
        .frame(width: 300)
    }

    @ViewBuilder
    private func row(_ summary: AgentConversationSummary) -> some View {
        let isCurrent = summary.id == controller.conversationID
        HStack(spacing: 8) {
            Circle()
                .fill(isCurrent ? SettingsColors.accent : Color.clear)
                .frame(width: 6, height: 6)
            if renamingID == summary.id {
                TextField("Title", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($renameFocused)
                    .onSubmit { commitRename(summary.id) }
                    .onExitCommand { renamingID = nil }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.title)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(summary.updatedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if confirmDeleteID == summary.id {
                Button("Delete", role: .destructive) {
                    controller.deleteConversation(summary.id)
                    confirmDeleteID = nil
                }
                .buttonStyle(.glassProminent)
                .tint(SettingsColors.danger)
                .controlSize(.small)
                Button("Cancel") { confirmDeleteID = nil }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            } else if renamingID != summary.id && (hoveredID == summary.id || isCurrent) {
                rowButton("pencil", help: "Rename") { startRename(summary) }
                rowButton("trash", help: "Delete") { confirmDeleteID = summary.id }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hoveredID == summary.id ? Color(nsColor: Colors.hoverBg) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? summary.id : (hoveredID == summary.id ? nil : hoveredID) }
        .onTapGesture {
            guard renamingID == nil, confirmDeleteID == nil, !controller.isRunning else { return }
            controller.openConversation(summary.id)
            onDone()
        }
        .contextMenu {
            Button("Rename…") { startRename(summary) }
            Button("Delete…", role: .destructive) { confirmDeleteID = summary.id }
        }
        .help(controller.isRunning ? "Stop the agent to switch chats" : summary.title)
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .help(help)
    }

    private func startRename(_ summary: AgentConversationSummary) {
        confirmDeleteID = nil
        renameDraft = summary.title
        renamingID = summary.id
        renameFocused = true
    }

    private func commitRename(_ id: UUID) {
        controller.renameConversation(id, to: renameDraft)
        renamingID = nil
    }
}
