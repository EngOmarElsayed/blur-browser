import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(SettingsStore.Keys.restoreTabsOnLaunch) var restoreTabsOnLaunch: Bool = false
    @State private var store = SettingsStore.shared
    @State private var isDefaultBrowser = false

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    if isDefaultBrowser {
                        Label("Default", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12, weight: .medium))
                    } else {
                        Button("Set as Default", action: setAsDefaultBrowser)
                            .buttonStyle(.glassProminent)
                            .tint(SettingsColors.accent)
                    }
                } label: {
                    Text("Default Browser")
                    Text(isDefaultBrowser
                         ? "\(AppConstants.appName) is your default browser."
                         : "Make \(AppConstants.appName) your default web browser.")
                }
            }

            Section {
                Toggle(isOn: $restoreTabsOnLaunch) {
                    Text("Restore tabs on launch")
                    Text("Reopen the tabs you had open when you last quit.")
                }
                .toggleStyle(.switch)
                .tint(SettingsColors.accent)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { checkDefaultBrowser() }
    }

    private func checkDefaultBrowser() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        if let defaultBrowser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) {
            let defaultBundleID = Bundle(url: defaultBrowser)?.bundleIdentifier
            isDefaultBrowser = (defaultBundleID == bundleID)
        }
    }

    private func setAsDefaultBrowser() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: "http"
        ) { error in
            if let error {
                print("[Settings] Failed to set default for http: \(error)")
            }
        }
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: "https"
        ) { error in
            if let error {
                print("[Settings] Failed to set default for https: \(error)")
            }
        }
        // Recheck after a short delay (macOS shows a confirmation dialog)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            checkDefaultBrowser()
        }
    }
}

// MARK: - Settings Text Field

struct SettingsTextField: View {
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
    }
}

// MARK: - Settings Picker

struct SettingsPicker<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options) { option in
                Text(label(option)).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Settings Toggle

/// Native switch, tinted with the theme accent. Kept as a wrapper so every
/// settings pane gets the same control.
struct SettingsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(SettingsColors.accent)
    }
}
