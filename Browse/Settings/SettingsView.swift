import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case appearance = "Appearance"
    case privacy = "Privacy"
    case permissions = "Permissions"
    case shortcuts = "Shortcuts"
    case about = "About"
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var themeStore = ThemeStore.shared

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(SettingsColors.chrome)

            VStack(alignment: .center, spacing: 0) {
                // Title bar
                titleBar

                // Tab bar
                tabBar
                    .padding(.bottom, 8)

                // Content area
                contentArea
            }
            .padding(8)
        }
        .frame(width: 800, height: 450)
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(alignment: .center) {
            Button {
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(SettingsColors.chromeFgPrimary)
                    .padding(.leading, 16)
            }
            .buttonStyle(.plain)

            Spacer()

            // Title
            Text("Settings")
                .font(.custom(Typography.fontFamily, size: Typography.headingSize).weight(.semibold))
                .foregroundStyle(SettingsColors.chromeFgPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer()

            Image(systemName: "xmark")
                .padding(.leading, 16)
                .opacity(0.0)
        }
        .frame(height: 36)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.custom(Typography.fontFamily, size: Typography.bodySize).weight(selectedTab == tab ? .semibold : .medium))
                        .foregroundStyle(selectedTab == tab ? Color(nsColor: Colors.onSurfacePrimary) : SettingsColors.chromeFgSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(themeStore.isDark ? 0.98 : 1.0))
                                    .shadow(color: Color.black.opacity(0.04), radius: 3, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 32)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ZStack {
            UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 7.5,
                bottomTrailingRadius: 7.5,
                topTrailingRadius: 8
            )
            .fill(SettingsColors.surface)

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .privacy:
                    PrivacySettingsView()
                case .permissions:
                    SitePermissionsSettingsView()
                case .shortcuts:
                    ShortcutsSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .padding([.horizontal, .top], 20)
        }
    }
}

// MARK: - Traffic Light Button

private struct TrafficLightButton: View {
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .opacity(isHovered ? 0.8 : 1.0)
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
    }
}
