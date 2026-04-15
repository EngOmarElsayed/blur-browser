import SwiftUI

struct AboutSettingsView: View {
    private let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }()

    private let buildNumber: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2024.12.15"
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App icon
                appIcon

                // App name
                Text("Blur-Browser")
                    .font(.custom(Typography.fontFamily, size: 22).weight(.bold))
                    .foregroundStyle(SettingsColors.fgPrimary)

                // Version info
                Text("Version \(appVersion)")
                    .font(.custom(Typography.fontFamily, size: 13))
                    .foregroundStyle(SettingsColors.fgSecondary)

                Text("Build \(buildNumber) (arm64)")
                    .font(.custom(Typography.fontFamily, size: 11))
                    .foregroundStyle(SettingsColors.fgSecondary)

                // Divider
                Rectangle()
                    .fill(SettingsColors.borderLight)
                    .frame(width: 200, height: 1)

                // Copyright
                Text("© 2024 Blur-Browser. All rights reserved.")
                    .font(.custom(Typography.fontFamily, size: 11))
                    .foregroundStyle(SettingsColors.fgSecondary)

                // Links
                HStack(spacing: 16) {
                    aboutLink("Website")
                    aboutLink("Privacy Policy")
                    aboutLink("License")
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - App Icon

    private var appIcon: some View {
        ZStack {
            // Outer squircle with gradient
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#A596D0"),
                            Color(hex: "#6BADE0"),
                            Color(hex: "#38BFD0")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .shadow(color: Color(hex: "#6BADE0").opacity(0.25), radius: 10, x: 0, y: 6)

            // Inner frosted square
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#D4CEE8"),
                            Color(hex: "#B8D5EE"),
                            Color(hex: "#A8DDE3")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
                .frame(width: 64, height: 64)
        }
    }

    // MARK: - Link

    private func aboutLink(_ title: String) -> some View {
        Text(title)
            .font(.custom(Typography.fontFamily, size: 11))
            .foregroundStyle(SettingsColors.accent)
            .onTapGesture {
                // Links are decorative in the settings panel
            }
    }
}
