import SwiftUI
import SwiftData
import WebKit

struct PrivacySettingsView: View {
    @State private var cookies: [HTTPCookie] = []
    @State private var selectedCookieIDs = Set<String>()
    @State private var searchText = ""
    @State private var showClearHistoryConfirm = false
    @State private var showClearDataConfirm = false
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteSelectedConfirm = false

    private var filteredCookies: [HTTPCookie] {
        if searchText.isEmpty { return cookies }
        let query = searchText.lowercased()
        return cookies.filter {
            $0.domain.lowercased().contains(query) ||
            $0.name.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Cookies section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cookies")
                        .font(.custom(Typography.fontFamily, size: 14).weight(.semibold))
                        .foregroundStyle(SettingsColors.fgPrimary)

                    Spacer()

                    // Search field
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsColors.fgSecondary)
                        TextField("Search cookies...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.custom(Typography.fontFamily, size: 12))
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 200, height: 28)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(SettingsColors.borderLight, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Cookie table
                SettingsTable {
                    // Header
                    SettingsTableHeader {
                        SettingsTableHeaderCell("Domain", flex: 3)
                        SettingsTableHeaderCell("Name", flex: 2)
                        SettingsTableHeaderCell("Expires", flex: 2)
                    }

                    // Rows
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredCookies) { cookie in
                                SettingsTableRow {
                                    SettingsTableCell(cookie.domain, flex: 3)
                                    SettingsTableCell(cookie.name, flex: 2)
                                    SettingsTableCell(cookieExpiry(cookie), flex: 2)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)

                // Buttons
                HStack(spacing: 8) {
                    SettingsSecondaryButton("Delete Selected") {
                        showDeleteSelectedConfirm = true
                    }
                    .disabled(selectedCookieIDs.isEmpty)
                    .confirmationDialog("Delete selected cookies?", isPresented: $showDeleteSelectedConfirm) {
                        Button("Delete", role: .destructive) { deleteSelectedCookies() }
                    }

                    SettingsDestructiveButton("Delete All") {
                        showDeleteAllConfirm = true
                    }
                    .confirmationDialog("Delete all cookies?", isPresented: $showDeleteAllConfirm) {
                        Button("Delete All", role: .destructive) { deleteAllCookies() }
                    }
                }
            }

            // Data Management section
            VStack(alignment: .leading, spacing: 10) {
                Text("Data Management")
                    .font(.custom(Typography.fontFamily, size: 14).weight(.semibold))
                    .foregroundStyle(SettingsColors.fgPrimary)

                HStack(spacing: 8) {
                    SettingsSecondaryButton("Clear Browsing History") {
                        showClearHistoryConfirm = true
                    }
                    .confirmationDialog("Clear all browsing history?", isPresented: $showClearHistoryConfirm) {
                        Button("Clear History", role: .destructive) { clearHistory() }
                    }

                    SettingsSecondaryButton("Clear All Website Data") {
                        showClearDataConfirm = true
                    }
                    .confirmationDialog("Clear all website data?", isPresented: $showClearDataConfirm) {
                        Button("Clear All Data", role: .destructive) { clearAllWebsiteData() }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await loadCookies() }
    }

    // MARK: - Helpers

    private func cookieExpiry(_ cookie: HTTPCookie) -> String {
        if let date = cookie.expiresDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM yyyy"
            return formatter.string(from: date)
        }
        return "Session"
    }

    // MARK: - Actions

    private func loadCookies() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let allCookies = await store.allCookies()
        cookies = allCookies.sorted { $0.domain < $1.domain }
    }

    private func deleteSelectedCookies() {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let toDelete = cookies.filter { selectedCookieIDs.contains($0.id) }
        Task {
            for cookie in toDelete { await store.deleteCookie(cookie) }
            selectedCookieIDs.removeAll()
            await loadCookies()
        }
    }

    private func deleteAllCookies() {
        let store = WKWebsiteDataStore.default().httpCookieStore
        Task {
            let all = await store.allCookies()
            for cookie in all { await store.deleteCookie(cookie) }
            selectedCookieIDs.removeAll()
            await loadCookies()
        }
    }

    private func clearHistory() {
        do {
            let schema = Schema([HistoryEntry.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            try context.delete(model: HistoryEntry.self)
            try context.save()
        } catch {
            print("[Settings] Failed to clear history: \(error)")
        }
    }

    private func clearAllWebsiteData() {
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(
            ofTypes: dataTypes,
            modifiedSince: .distantPast
        ) { [self] in
            Task { await loadCookies() }
        }
    }
}

// MARK: - HTTPCookie Identifiable Conformance

extension HTTPCookie: @retroactive Identifiable {
    public var id: String {
        "\(domain)|\(name)|\(path)"
    }
}

// MARK: - Reusable Settings Table Components

struct SettingsTable<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(SettingsColors.borderLight, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct SettingsTableHeader<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .frame(height: 32)
        .background(SettingsColors.chrome)
    }
}

struct SettingsTableHeaderCell: View {
    let text: String
    let fullwidth: Bool
    var flex: CGFloat = 1

    init(_ text: String, flex: CGFloat = 1, fullwidth: Bool = true) {
        self.text = text
        self.flex = flex
        self.fullwidth = fullwidth
    }

    var body: some View {
        Text(text)
            .font(.custom(Typography.fontFamily, size: 11).weight(.semibold))
            .foregroundStyle(SettingsColors.fgSecondary)
            .frame(maxWidth: fullwidth ? .infinity: nil, alignment: .leading)
            .layoutPriority(flex)
            .padding(.horizontal, 12)
    }
}

struct SettingsTableRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .frame(height: 32)
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SettingsColors.borderLight)
                .frame(height: 1)
        }
    }
}

struct SettingsTableCell: View {
    let text: String
    var flex: CGFloat = 1

    init(_ text: String, flex: CGFloat = 1) {
        self.text = text
        self.flex = flex
    }

    var body: some View {
        Text(text)
            .font(.custom(Typography.fontFamily, size: 12))
            .foregroundStyle(SettingsColors.fgPrimary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(flex)
            .padding(.horizontal, 12)
    }
}

// MARK: - Settings Buttons

struct SettingsSecondaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(Typography.fontFamily, size: 12))
                .foregroundStyle(SettingsColors.fgPrimary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(SettingsColors.borderLight, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

struct SettingsDestructiveButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom(Typography.fontFamily, size: 12))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(SettingsColors.danger)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
