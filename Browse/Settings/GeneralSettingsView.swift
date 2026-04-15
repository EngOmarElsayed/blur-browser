import SwiftUI

struct GeneralSettingsView: View {
    @State private var store = SettingsStore.shared
    @State private var isDefaultBrowser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Default Browser
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Default Browser")
                        .font(.custom(Typography.fontFamily, size: 13))
                        .foregroundStyle(SettingsColors.fgPrimary)

                    Text(isDefaultBrowser ? "Blur-Browser is your default browser." : "Make Blur-Browser your default web browser.")
                        .font(.custom(Typography.fontFamily, size: 11))
                        .foregroundStyle(SettingsColors.fgSecondary)
                }

                Spacer()

                if isDefaultBrowser {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#22C55E"))
                        Text("Default")
                            .font(.custom(Typography.fontFamily, size: 12).weight(.medium))
                            .foregroundStyle(Color(hex: "#22C55E"))
                    }
                } else {
                    Button {
                        setAsDefaultBrowser()
                    } label: {
                        Text("Set as Default")
                            .font(.custom(Typography.fontFamily, size: 12).weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background(SettingsColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .foregroundStyle(SettingsColors.borderLight)

            // Homepage
            VStack(alignment: .leading, spacing: 6) {
                Text("Homepage")
                    .font(.custom(Typography.fontFamily, size: 12))
                    .foregroundStyle(SettingsColors.fgSecondary)

                SettingsTextField(text: $store.homepageURL, placeholder: "https://google.com")
            }

            // Search Engine
            VStack(alignment: .leading, spacing: 6) {
                Text("Search Engine")
                    .font(.custom(Typography.fontFamily, size: 12))
                    .foregroundStyle(SettingsColors.fgSecondary)

                SettingsPicker(selection: $store.searchEngine, options: SearchEngine.allCases) { engine in
                    engine.displayName
                }
            }

            // Restore tabs on launch
            HStack {
                Text("Restore tabs on launch")
                    .font(.custom(Typography.fontFamily, size: 13))
                    .foregroundStyle(SettingsColors.fgPrimary)

                Spacer()

                SettingsToggle(isOn: $store.restoreTabsOnLaunch)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .textFieldStyle(.plain)
            .font(.custom(Typography.fontFamily, size: 13))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(SettingsColors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
        .font(.custom(Typography.fontFamily, size: 13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 32)
        .background(Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(SettingsColors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Settings Toggle

struct SettingsToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.toggle()
            }
        } label: {
            let _ = print("isOn: \(isOn)")
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? SettingsColors.accent : Color(hex: "#D0D5EB"))
                    .frame(width: 44, height: 24)

                Circle()
                    .fill(Color.white)
                    .frame(width: 18, height: 18)
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
