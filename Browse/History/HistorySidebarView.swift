import SwiftUI

struct HistorySidebarView: View {
    let historyStore: HistoryStore
    let tabManager: TabManager
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // History header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 14))
                        .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                    Text("History")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: Layout.historyHeaderHeight)

            Divider()

            // Search
            HistorySearchView(searchText: $searchText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // History list
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    let groups = searchText.isEmpty
                        ? historyStore.groupedEntries
                        : [HistoryStore.GroupedHistory(
                            id: "search",
                            label: "Results",
                            entries: historyStore.search(query: searchText)
                          )]

                    ForEach(groups) { group in
                        Section {
                            ForEach(group.entries, id: \.url) { entry in
                                historyRow(entry)
                            }
                        } header: {
                            Text(group.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: Colors.sidebarBg))
                        }
                    }
                }
            }
        }
    }

    private func historyRow(_ entry: HistoryEntry) -> some View {
        Button {
            tabManager.navigate(to: entry.url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                    .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: Colors.foregroundPrimary))
                        .lineLimit(1)
                    Text(formattedTime(entry.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: Colors.foregroundMuted))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .frame(height: Layout.historyItemHeight)
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
