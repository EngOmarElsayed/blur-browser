import SwiftUI

struct AppearanceSettingsView: View {
    @State private var themeStore = ThemeStore.shared

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var gridPanelFill: Color {
        Color(nsColor: themeStore.chromeColor).opacity(themeStore.isDark ? 0.28 : 0.10)
    }

    private var gridPanelBorder: Color {
        Color(nsColor: themeStore.borderColor).opacity(themeStore.isDark ? 0.90 : 0.45)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme")
                    .font(.custom(Typography.fontFamily, size: 13))
                    .foregroundStyle(SettingsColors.fgPrimary)

                Text("Choose a theme. The selected theme colors the sidebar, toolbar, and all panels. Each theme comes with a curated set of new-tab wallpapers.")
                    .font(.custom(Typography.fontFamily, size: 11))
                    .foregroundStyle(SettingsColors.fgSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Theme.all) { theme in
                        ThemeCard(
                            theme: theme,
                            isSelected: theme.id == themeStore.currentThemeID
                        ) {
                            themeStore.select(theme.id)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(gridPanelFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(gridPanelBorder, lineWidth: 1)
                )
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: Theme
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var themeStore = ThemeStore.shared

    private var cardFill: Color {
        Color(nsColor: themeStore.chromeColor).opacity(themeStore.isDark ? 0.62 : 0.20)
    }

    private var cardBorder: Color {
        if isSelected {
            return Color(nsColor: theme.accentColor)
        }
        return Color(nsColor: themeStore.borderColor).opacity(themeStore.isDark ? 0.92 : 0.55)
    }

    private var cardTitleColor: Color {
        Color(nsColor: themeStore.foregroundColor)
    }

    private var cardSubtitleColor: Color {
        Color(nsColor: themeStore.foregroundColor.withAlphaComponent(themeStore.isDark ? 0.74 : 0.58))
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                preview
                info
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(cardBorder, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(
                color: isSelected
                    ? Color(nsColor: theme.accentColor).opacity(0.2)
                    : Color.black.opacity(themeStore.isDark ? 0.20 : 0.04),
                radius: isSelected ? 8 : 2,
                x: 0, y: isSelected ? 4 : 1
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityHint(theme.mood)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var preview: some View {
        ZStack(alignment: .topTrailing) {
            // Mini browser chrome strip
            HStack(spacing: 4) {
                Circle().fill(Color(nsColor: theme.accentColor)).frame(width: 6, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(height: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color(nsColor: theme.borderColor), lineWidth: 0.5)
                    )
                Spacer()
                Text("Aa")
                    .font(.custom(Typography.fontFamily, size: 9).weight(.semibold))
                    .foregroundStyle(Color(nsColor: theme.foregroundColor))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .frame(height: 68)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: theme.chromeColor))

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(nsColor: theme.accentColor), .white)
                    .padding(6)
            }
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 10
            )
        )
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(theme.displayName)
                .font(.custom(Typography.fontFamily, size: 12).weight(.semibold))
                .foregroundStyle(cardTitleColor)
            Text(theme.mood)
                .font(.custom(Typography.fontFamily, size: 10))
                .foregroundStyle(cardSubtitleColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
