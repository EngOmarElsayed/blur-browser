import SwiftUI

struct HistoryPanelView: View {
    let historyStore: HistoryStore
    let tabManager: TabManager
    var onDismiss: () -> Void
    @State private var searchText = ""

    private var filteredGroups: [HistoryStore.GroupedHistory] {
        if searchText.isEmpty {
            return historyStore.groupedEntries
        } else {
            let results = historyStore.search(query: searchText)
            return results.isEmpty ? [] : [HistoryStore.GroupedHistory(id: "search", label: "Results", entries: results)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — matches sidebar style with top padding for titlebar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    Text("History")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            // Search field — matches sidebar search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))

                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: Colors.foregroundSecondary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: Colors.surfacePrimary))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: Colors.borderLight), lineWidth: 1)
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider()

            // Grouped history list
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if filteredGroups.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredGroups) { group in
                            Section {
                                ForEach(group.entries, id: \.url) { entry in
                                    historyRow(entry)
                                }
                            } header: {
                                Text(group.label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(nsColor: Colors.sidebarBg))
                            }
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: Colors.sidebarBg))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 40)
            Image(systemName: "clock")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(nsColor: Colors.borderLight))
            Text("No history yet")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        Button {
            tabManager.navigate(to: entry.url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    .frame(width: 16, height: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title.isEmpty ? entry.url : entry.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                        .lineLimit(1)
                    Text(formattedTime(entry.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { tabManager.navigate(to: entry.url) }
            Button("Open in New Tab") { tabManager.addNewTab(url: URL(string: entry.url)) }
            Divider()
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url, forType: .string)
            }
            Button("Delete") { historyStore.deleteEntry(entry) }
        }
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
