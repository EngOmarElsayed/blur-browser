import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case appearance = "Appearance"
    case privacy = "Privacy"
    case permissions = "Permissions"
    case shortcuts = "Shortcuts"
    case ai = "AI"
    case about = "About"
}

extension SettingsTab {
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .privacy: "hand.raised"
        case .permissions: "lock.shield"
        case .shortcuts: "command"
        case .ai: "sparkles"
        case .about: "info.circle"
        }
    }
}

/// Which Settings tab is showing — shared so other UI can deep-link a tab.
@Observable
@MainActor
final class SettingsRouter {
    static let shared = SettingsRouter()
    var selectedTab: SettingsTab = .general
}

struct SettingsView: View {
    @State private var router = SettingsRouter.shared

    var body: some View {
        VStack(spacing: 0) {
            // Title — shares the transparent titlebar row with the native close button
            Text("Settings")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(height: 28)
                .frame(maxWidth: .infinity)

            Picker("Section", selection: $router.selectedTab.animation(.smooth(duration: 0.2))) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)
            .fixedSize()
            .padding(.top, 6)
            .padding(.bottom, 14)

            contentArea
        }
        .frame(width: 800, height: 450)
        .background(.background)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        Group {
            switch router.selectedTab {
            case .general:
                // Native grouped Form brings its own insets
                GeneralSettingsView()
            case .appearance:
                AppearanceSettingsView().settingsPanePadding()
            case .privacy:
                PrivacySettingsView().settingsPanePadding()
            case .permissions:
                SitePermissionsSettingsView().settingsPanePadding()
            case .shortcuts:
                ShortcutsSettingsView().settingsPanePadding()
            case .ai:
                // Native grouped Form brings its own insets
                AISettingsView()
            case .about:
                AboutSettingsView().settingsPanePadding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: Colors.surfaceSecondary))
        .overlay(alignment: .top) { Divider() }
    }
}

private extension View {
    func settingsPanePadding() -> some View {
        padding([.horizontal, .top], 20)
    }
}
