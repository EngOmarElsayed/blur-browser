import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case privacy = "Privacy"
    case permissions = "Permissions"
    case shortcuts = "Shortcuts"
    case about = "About"
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        ZStack {
            // Window chrome background
            RoundedRectangle(cornerRadius: 11)
                .fill(SettingsColors.chrome)
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .strokeBorder(SettingsColors.windowBorder, lineWidth: 3.5)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)

            VStack(alignment: .center, spacing: 0) {
                // Title bar
                titleBar

                // Tab bar
                tabBar
                    .padding(.bottom, 8)

                // Content area
                contentArea
            }
            .padding(3.5) // Inside the border
        }
        .frame(width: 800, height: 450)
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        ZStack {
            // Traffic lights
            HStack(spacing: 8) {
                TrafficLightButton(color: SettingsColors.trafficRed) {
                    NSApp.keyWindow?.close()
                }
                TrafficLightButton(color: SettingsColors.trafficYellow) {
                    NSApp.keyWindow?.miniaturize(nil)
                }
                TrafficLightButton(color: SettingsColors.trafficGreen) {}
                    .opacity(0.8)
                Spacer()
            }
            .padding(.leading, 16)

            // Title
            Text("Settings")
                .font(.custom(Typography.fontFamily, size: 13).weight(.semibold))
                .foregroundStyle(SettingsColors.fgPrimary)
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
                        .font(.custom(Typography.fontFamily, size: 12).weight(selectedTab == tab ? .medium : .regular))
                        .foregroundStyle(selectedTab == tab ? SettingsColors.fgPrimary : SettingsColors.fgSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white)
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
            .padding(20)
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
