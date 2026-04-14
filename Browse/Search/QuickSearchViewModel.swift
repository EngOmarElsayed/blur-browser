import AppKit
import Observation

enum QuickSearchResultType: String {
    case openTab = "Switch to Tab"
    case history = "History"
    case suggestion = "Search Suggestions"
}

struct QuickSearchResult: Identifiable {
    let id = UUID()
    let type: QuickSearchResultType
    let title: String
    let subtitle: String
    let icon: String
    var tabID: UUID?
}

@Observable
@MainActor
final class QuickSearchViewModel {
    var searchText: String = ""
    var results: [QuickSearchResult] = []
    var selectedID: UUID?
    var isLoading: Bool = false
    var navigateInNewTab: Bool = false

    private let tabManager: TabManager
    private let historyStore: HistoryStore
    private var suggestTask: Task<Void, Never>?

    init(tabManager: TabManager, historyStore: HistoryStore) {
        self.tabManager = tabManager
        self.historyStore = historyStore
    }

    var selectedResult: QuickSearchResult? {
        guard let id = selectedID else { return nil }
        return results.first { $0.id == id }
    }

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return results.firstIndex { $0.id == id }
    }

    func updateResults() {
        suggestTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            results = recentHistory()
            selectedID = results.first?.id
            return
        }

        var all: [QuickSearchResult] = []

        // Matching open tabs
        let matchedTabs = tabManager.tabs.filter {
            $0.displayTitle.localizedCaseInsensitiveContains(query) ||
            $0.displayURL.localizedCaseInsensitiveContains(query)
        }
        all += matchedTabs.prefix(3).map {
            QuickSearchResult(
                type: .openTab,
                title: $0.displayTitle,
                subtitle: $0.displayURL,
                icon: "square.stack",
                tabID: $0.id
            )
        }

        // History matches
        let historyMatches = historyStore.search(query: query)
        all += historyMatches.prefix(5).map {
            QuickSearchResult(
                type: .history,
                title: $0.title,
                subtitle: $0.url,
                icon: "clock"
            )
        }

        results = all
        selectedID = all.first?.id

        // Fetch Google suggestions
        suggestTask = Task {
            await fetchSuggestions(for: query)
        }
    }

    private func recentHistory() -> [QuickSearchResult] {
        historyStore.entries.prefix(5).map {
            QuickSearchResult(
                type: .history,
                title: $0.title,
                subtitle: $0.url,
                icon: "clock"
            )
        }
    }

    private func fetchSuggestions(for query: String) async {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(AppConstants.googleSuggestURL)\(encoded)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }

            if let json = try JSONSerialization.jsonObject(with: data) as? [Any],
               let suggestions = json[safe: 1] as? [String] {
                let suggestResults = suggestions.prefix(5).map {
                    QuickSearchResult(
                        type: .suggestion,
                        title: $0,
                        subtitle: "Search Google",
                        icon: "magnifyingglass"
                    )
                }
                results += suggestResults
            }
        } catch {
            // Ignore network errors for suggestions
        }
    }

    func selectResult() {
        if navigateInNewTab {
            tabManager.addNewTab()
        }

        guard let result = selectedResult else {
            // No selection — treat text as direct navigation
            if !searchText.isEmpty {
                tabManager.navigate(to: searchText)
            }
            return
        }

        switch result.type {
        case .openTab:
            if let tabID = result.tabID,
               let tab = tabManager.tabs.first(where: { $0.id == tabID }) {
                tabManager.selectTab(tab)
            }
        case .history:
            tabManager.navigate(to: result.subtitle)
        case .suggestion:
            tabManager.navigate(to: result.title)
        }
    }

    func moveSelectionUp() {
        guard let idx = selectedIndex, idx > 0 else { return }
        selectedID = results[idx - 1].id
    }

    func moveSelectionDown() {
        guard let idx = selectedIndex, idx < results.count - 1 else {
            // If nothing selected, select first
            if selectedID == nil { selectedID = results.first?.id }
            return
        }
        selectedID = results[idx + 1].id
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
