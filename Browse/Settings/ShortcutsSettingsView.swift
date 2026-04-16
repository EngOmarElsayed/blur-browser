import SwiftUI

struct ShortcutsSettingsView: View {

    private struct ShortcutEntry: Identifiable {
        let id = UUID()
        let action: String
        let shortcut: String
    }

    private let shortcuts: [ShortcutEntry] = [
        // File
        ShortcutEntry(action: "New Tab", shortcut: "⌘T"),
        ShortcutEntry(action: "Quick Search", shortcut: "⌘K"),
        ShortcutEntry(action: "New Window", shortcut: "⌘N"),
        ShortcutEntry(action: "Open Location", shortcut: "⌘L"),
        ShortcutEntry(action: "Close Tab", shortcut: "⌘W"),
        // Edit
        ShortcutEntry(action: "Find in Page", shortcut: "⌘F"),
        ShortcutEntry(action: "Find Next", shortcut: "⌘G"),
        ShortcutEntry(action: "Find Previous", shortcut: "⇧⌘G"),
        ShortcutEntry(action: "Copy URL", shortcut: "⇧⌘C"),
        // View
        ShortcutEntry(action: "Toggle Sidebar", shortcut: "⌘\\"),
        ShortcutEntry(action: "Focus Mode", shortcut: "⇧⌘F"),
        ShortcutEntry(action: "Toggle Address Bar", shortcut: "⇧⌘A"),
        ShortcutEntry(action: "Reload", shortcut: "⌘R"),
        ShortcutEntry(action: "Hard Reload", shortcut: "⇧⌘R"),
        ShortcutEntry(action: "Web Inspector", shortcut: "⌥⌘C"),
        // History
        ShortcutEntry(action: "Show History", shortcut: "⌘Y"),
        ShortcutEntry(action: "Back", shortcut: "⌘["),
        ShortcutEntry(action: "Forward", shortcut: "⌘]"),
        // Window
        ShortcutEntry(action: "Next Tab", shortcut: "⇧⌘]"),
        ShortcutEntry(action: "Previous Tab", shortcut: "⇧⌘["),
        ShortcutEntry(action: "Select Tab 1–9", shortcut: "⌘1 – ⌘9"),
        // App
        ShortcutEntry(action: "Settings", shortcut: "⌘,"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.custom(Typography.fontFamily, size: 14).weight(.semibold))
                    .foregroundStyle(SettingsColors.fgPrimary)

                SettingsTable {
                    // Header
                    SettingsTableHeader {
                        Text("Action")
                            .font(.custom(Typography.fontFamily, size: 11).weight(.semibold))
                            .foregroundStyle(SettingsColors.fgSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)

                        Text("Shortcut")
                            .font(.custom(Typography.fontFamily, size: 11).weight(.semibold))
                            .foregroundStyle(SettingsColors.fgSecondary)
                            .frame(width: 140, alignment: .trailing)
                            .padding(.trailing, 12)
                    }
                    .frame(height: 28)

                    // Rows
                    LazyVStack(spacing: 0) {
                        ForEach(shortcuts) { entry in
                            HStack(spacing: 0) {
                                Text(entry.action)
                                    .font(.custom(Typography.fontFamily, size: 12))
                                    .foregroundStyle(SettingsColors.fgPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)

                                Text(entry.shortcut)
                                    .font(.custom(Typography.monoFamily, size: 11))
                                    .foregroundStyle(SettingsColors.fgSecondary)
                                    .frame(width: 140, alignment: .trailing)
                                    .padding(.trailing, 12)
                            }
                            .frame(height: 26)
                            .background(Color.white)
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(SettingsColors.borderLight)
                                    .frame(height: 1)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.hidden)
    }
}
