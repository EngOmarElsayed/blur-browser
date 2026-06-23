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
        ScrollView {
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
                        // Header — leading checkbox toggles select-all on the
                        // currently-filtered view. When the search field narrows
                        // the list, the toggle only acts on what's visible.
                        SettingsTableHeader {
                            Button {
                                toggleSelectAll()
                            } label: {
                                Image(systemName: selectAllIconName)
                                    .font(.system(size: 13))
                                    .foregroundStyle(allFilteredSelected ? SettingsColors.accent : SettingsColors.fgSecondary)
                                    .frame(width: 28, height: 32)
                            }
                            .buttonStyle(.plain)
                            .help(allFilteredSelected ? "Deselect all" : "Select all")
                            .disabled(filteredCookies.isEmpty)

                            SettingsTableHeaderCell("Domain", flex: 3)
                            SettingsTableHeaderCell("Name", flex: 2)
                            SettingsTableHeaderCell("Expires", flex: 2)
                        }

                        // Rows — entire row is a click target; checkbox is just
                        // a visual indicator of `selectedCookieIDs` membership.
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredCookies) { cookie in
                                    let isSelected = selectedCookieIDs.contains(cookie.id)
                                    Button {
                                        toggleCookieSelection(cookie)
                                    } label: {
                                        SettingsTableRow(
                                            backgroundColor: isSelected
                                                ? SettingsColors.accent.opacity(0.12)
                                                : .white
                                        ) {
                                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                                .font(.system(size: 13))
                                                .foregroundStyle(isSelected ? SettingsColors.accent : SettingsColors.fgSecondary)
                                                .frame(width: 28)
                                            SettingsTableCell(cookie.domain, flex: 3)
                                            SettingsTableCell(cookie.name, flex: 2)
                                            SettingsTableCell(cookieExpiry(cookie), flex: 2)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)

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
        }
        .scrollIndicators(.hidden)
        .task { await loadCookies() }
    }

    // MARK: - Selection helpers

    /// True when every cookie currently visible (after the search filter)
    /// is in `selectedCookieIDs`. Used to flip the header checkbox state.
    private var allFilteredSelected: Bool {
        !filteredCookies.isEmpty && filteredCookies.allSatisfy { selectedCookieIDs.contains($0.id) }
    }

    /// Three-state header icon: filled when all are selected, partial when
    /// some are, empty otherwise. macOS's standard tri-state pattern.
    private var selectAllIconName: String {
        if allFilteredSelected { return "checkmark.square.fill" }
        let anySelected = filteredCookies.contains { selectedCookieIDs.contains($0.id) }
        return anySelected ? "minus.square.fill" : "square"
    }

    private func toggleSelectAll() {
        if allFilteredSelected {
            // All visible are selected → clear selection for the visible set
            for c in filteredCookies { selectedCookieIDs.remove(c.id) }
        } else {
            for c in filteredCookies { selectedCookieIDs.insert(c.id) }
        }
    }

    private func toggleCookieSelection(_ cookie: HTTPCookie) {
        if selectedCookieIDs.contains(cookie.id) {
            selectedCookieIDs.remove(cookie.id)
        } else {
            selectedCookieIDs.insert(cookie.id)
        }
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
            let schema = Schema([BrowserHistoryEntry.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            try context.delete(model: BrowserHistoryEntry.self)
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
    let backgroundColor: Color
    @ViewBuilder let content: Content

    init(backgroundColor: Color = .white, @ViewBuilder content: () -> Content) {
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .frame(height: 32)
        .background(backgroundColor)
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
