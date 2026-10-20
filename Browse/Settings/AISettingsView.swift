import SwiftUI

/// Settings → AI: the model providers the Agent pane can use (keys in the
/// Keychain), which one is active, and the consent log.
struct AISettingsView: View {
    private var store: AIProviderStore { .shared }
    @State private var editingID: UUID?
    @State private var animateActions = AgentActionSettings.animate
    @State private var actionSpeed = AgentActionSettings.speed
    @State private var saveChats = AgentChatSettings.saveConversations
    @State private var requireTouchID = AgentChatSettings.requireAuthentication
    @State private var autoLockMinutes = AgentChatSettings.autoLockMinutes
    @State private var confirmDeleteChats = false
    private var vault: AgentConversationVault { .shared }

    private static let claudeModels: [(id: String, name: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-haiku-5-5", "Claude Haiku 5.5"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(store.providers) { config in
                    providerRow(config)
                }
            } header: {
                HStack {
                    Text("Model providers")
                    Spacer()
                    addMenu
                }
            } footer: {
                Text("The selected provider powers the Agent pane (⌥⌘A). API keys are stored in your Keychain on this Mac only; requests go straight to the endpoint you set.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let id = editingID, let config = store.providers.first(where: { $0.id == id }) {
                ProviderEditor(config: config, claudeModels: Self.claudeModels)
                    .id(id)
            }

            Section {
                Toggle(isOn: $animateActions) {
                    Text("Animate agent actions")
                    Text("Show a cursor that moves to what the agent clicks, and type one character at a time. Off: actions run as fast as possible, still as real clicks and keystrokes.")
                }
                .onChange(of: animateActions) { _, value in AgentActionSettings.animate = value }
                Picker("Speed", selection: $actionSpeed) {
                    ForEach(AgentActionSpeed.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!animateActions)
                .onChange(of: actionSpeed) { _, value in AgentActionSettings.speed = value }
            } header: {
                Text("Agent actions")
            }

            savedChatsSection

            Section {
                LabeledContent {
                    Button("Show in Finder") {
                        let url = AgentConsentLog.fileURL
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } else {
                            NSWorkspace.shared.open(url.deletingLastPathComponent())
                        }
                    }
                    .buttonStyle(.glass)
                } label: {
                    Text("Dangerous-mode consent log")
                    Text("Each time Dangerous mode is turned on or off, a record is appended here. Dangerous mode always resets when you quit.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { editingID = editingID ?? store.active.id }
    }

    private var savedChatsSection: some View {
        Section {
            Toggle(isOn: $saveChats) {
                Text("Save agent conversations")
                Text("Keep chats so you can pick them up later. Each one is encrypted on this Mac; page text attached with \"Include this page\" isn't kept.")
            }
            .onChange(of: saveChats) { _, value in vault.setSavingEnabled(value) }

            Toggle(isOn: $requireTouchID) {
                Text("Require Touch ID to view saved chats")
                Text("Falls back to your Mac password. Turning this off asks for Touch ID first.")
            }
            .disabled(!saveChats)
            .onChange(of: requireTouchID) { _, value in
                guard value != AgentChatSettings.requireAuthentication else { return }
                Task {
                    let applied = await vault.setRequireAuthentication(value)
                    if !applied { requireTouchID = AgentChatSettings.requireAuthentication }
                }
            }

            Picker("Lock after", selection: $autoLockMinutes) {
                ForEach(AgentChatSettings.autoLockChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
            }
            .disabled(!saveChats || !requireTouchID)
            .onChange(of: autoLockMinutes) { _, value in AgentChatSettings.autoLockMinutes = value }

            LabeledContent {
                HStack(spacing: 8) {
                    Button("Show in Finder") {
                        let url = AgentConversationVault.directory
                        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.glass)
                    Button("Delete All…", role: .destructive) { confirmDeleteChats = true }
                        .buttonStyle(.glass)
                }
            } label: {
                Text("Saved chats")
                Text(keyStatus)
            }
            .confirmationDialog("Delete all saved agent chats?", isPresented: $confirmDeleteChats) {
                Button("Delete All", role: .destructive) { vault.deleteAll() }
            } message: {
                Text("This removes every encrypted chat file. Chats open in a window are saved again if you keep using them.")
            }
        } header: {
            Text("Saved chats")
        } footer: {
            Text("Chats lock after the time above in the background or idle, and whenever the Mac sleeps or the screen locks. Providers still see whatever you send them.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var keyStatus: String {
        if let mode = vault.keyMode { return mode.description }
        return vault.state == .disabled ? "Saving is off." : "Unlock saved chats to see where the key is kept."
    }

    private func providerRow(_ config: AIProviderConfig) -> some View {
        let isActive = config.id == store.active.id
        return HStack(spacing: 10) {
            Button {
                store.select(config.id)
            } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? SettingsColors.accent : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(isActive ? "In use" : "Use this provider")

            VStack(alignment: .leading, spacing: 2) {
                Text(config.label)
                Text(subtitle(config))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if !store.isReady(config) {
                Text("No key")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SettingsColors.danger)
            }
            Button(editingID == config.id ? "Done" : "Edit") {
                editingID = editingID == config.id ? nil : config.id
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .contentShape(Rectangle())
        .onTapGesture { editingID = config.id }
    }

    private func subtitle(_ config: AIProviderConfig) -> String {
        "\(config.kind.label) · \(config.model)\(config.supportsTools ? "" : " · chat only")"
    }

    private var addMenu: some View {
        Menu {
            ForEach(AIProviderKind.allCases, id: \.self) { kind in
                Button(kind.label) { editingID = store.add(kind: kind).id }
            }
            Divider()
            Button("Local model (OpenAI-compatible)") {
                editingID = store.add(
                    kind: .openAICompatible, label: "Local model",
                    baseURL: "http://127.0.0.1:8080/v1", model: "local", supportsTools: false).id
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .fixedSize()
    }
}

// MARK: - Editor

/// Edits one provider. Text fields commit on submit or when focus leaves, so
/// the stored config isn't rewritten on every keystroke.
private struct ProviderEditor: View {
    let config: AIProviderConfig
    let claudeModels: [(id: String, name: String)]

    private var store: AIProviderStore { .shared }
    @State private var label = ""
    @State private var baseURL = ""
    @State private var model = ""
    @State private var keyDraft = ""
    @State private var status: String?

    var body: some View {
        Section {
            TextField("Name", text: $label)
                .onSubmit(commit)
            Picker("Type", selection: kindBinding) {
                ForEach(AIProviderKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            TextField("Base URL", text: $baseURL, prompt: Text(config.kind.defaultBaseURL))
                .font(.system(size: 12, design: .monospaced))
                .onSubmit(commit)
            if config.kind == .anthropic {
                Picker("Model", selection: modelBinding) {
                    ForEach(claudeModels, id: \.id) { Text($0.name).tag($0.id) }
                    if !claudeModels.contains(where: { $0.id == config.model }) {
                        Text(config.model).tag(config.model)
                    }
                }
            } else {
                TextField("Model", text: $model, prompt: Text(config.kind.defaultModel))
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(commit)
            }
            Toggle(isOn: toolsBinding) {
                Text("Browser tools")
                Text(config.supportsTools
                     ? "The model can read pages, open tabs, click and type, with Ask / Dangerous permissions."
                     : "Chat only: the current page's text is sent with each message. Turn on if the endpoint supports tool calls.")
            }

            LabeledContent {
                HStack(spacing: 8) {
                    SecureField(store.hasKey(config) ? "••••••••  (saved)" : (config.isLocal ? "Optional" : "Required"), text: $keyDraft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit(saveKey)
                    Button("Save", action: saveKey)
                        .buttonStyle(.glassProminent)
                        .tint(SettingsColors.accent)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if store.hasKey(config) {
                        Button("Remove", role: .destructive) {
                            store.removeKey(for: config)
                            status = "Removed."
                        }
                        .buttonStyle(.glass)
                    }
                }
            } label: {
                Text("API key")
                Text(status ?? "Stored in your Keychain.")
            }

            if config.isLocal {
                Text("Local servers need macOS Local Network access for Blur-Browser. If requests fail with “Local network prohibited”, run tools/relay.py and point this at http://127.0.0.1:<port>/v1 — see docs/ai-agent.md.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Delete Provider", role: .destructive) { store.remove(config.id) }
                    .buttonStyle(.glass)
                    .disabled(store.providers.count <= 1)
            }
        } header: {
            Text("Edit \(config.label)")
        }
        .onAppear {
            label = config.label
            baseURL = config.baseURL
            model = config.model
        }
        .onDisappear(perform: commit)
    }

    private var kindBinding: Binding<AIProviderKind> {
        Binding(get: { config.kind }, set: { kind in
            var updated = current
            guard kind != updated.kind else { return }
            // Switching type resets the endpoint and model to that type's defaults.
            updated.kind = kind
            updated.baseURL = kind.defaultBaseURL
            updated.model = kind.defaultModel
            baseURL = updated.baseURL
            model = updated.model
            store.update(updated)
        })
    }

    private var modelBinding: Binding<String> {
        Binding(get: { config.model }, set: { value in
            var updated = current
            updated.model = value
            model = value
            store.update(updated)
        })
    }

    private var toolsBinding: Binding<Bool> {
        Binding(get: { config.supportsTools }, set: { value in
            var updated = current
            updated.supportsTools = value
            store.update(updated)
        })
    }

    /// The config with uncommitted text-field edits applied.
    private var current: AIProviderConfig {
        var updated = store.providers.first { $0.id == config.id } ?? config
        let trimmedLabel = label.trimmingCharacters(in: .whitespaces)
        if !trimmedLabel.isEmpty { updated.label = trimmedLabel }
        updated.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
        if updated.baseURL.isEmpty { updated.baseURL = updated.kind.defaultBaseURL }
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)
        if !trimmedModel.isEmpty { updated.model = trimmedModel }
        return updated
    }

    private func commit() {
        guard store.providers.contains(where: { $0.id == config.id }) else { return }
        let updated = current
        if updated != config { store.update(updated) }
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        if store.setKey(key, for: config) {
            keyDraft = ""
            status = "Saved to Keychain."
        } else {
            status = "Couldn't save to Keychain."
        }
    }
}
