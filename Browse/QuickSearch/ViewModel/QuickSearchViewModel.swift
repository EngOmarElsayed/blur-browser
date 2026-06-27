//
//  QuickSearchViewModel.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 25/06/2026.
//

import AppKit
import Observation
import FactoryKit

@Observable
@MainActor
final class QuickSearchViewModel {
    var searchText: String = ""
    var results: [QuickSearchResult] = []
    var groupedResults: [QuickSearchResultType : [QuickSearchResult]] = [:]
    var selectedID: UUID?
    var navigateInNewTab: Bool = false

    private var suggestTask: Task<Void, Never>?
    @ObservationIgnored @Injected(\.fetchHistoryWithPredictUseCase) private var fetchHistoryWithPredictUseCase
    @ObservationIgnored private let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
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
            results = []
            groupedResults = [:]
            return
        }

        suggestTask = Task(priority: .high) {
            results = await fetchResultTaskGroup(for: query)
            groupedResults = Dictionary(grouping: results, by: \.type)
        }
    }

    func restViewModel() {
        groupedResults = [:]
        results = []
        searchText = ""
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
        guard let idx = selectedIndex, idx > 0 else {
            selectedID = nil
            return
        }

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

// MARK: - QuickSearchViewModel fetch methods
extension QuickSearchViewModel {
    private func fetchResultTaskGroup(for searchText: String) async -> [QuickSearchResult] {
        return await withTaskGroup(of: [QuickSearchResult].self, returning: [QuickSearchResult].self) { group in
            group.addTask { await self.fetchResultFromHistory(for: searchText) }
            group.addTask { await self.fetchResultFromTabs(for: searchText) }
            group.addTask { await self.fetchSuggestions(for: searchText) }

            var results: [QuickSearchResult] = []
            for await result in group {
                if Task.isCancelled {
                    group.cancelAll()
                    return []
                } else {
                    results.append(contentsOf: result)
                }
            }

            return results
        }
    }

    @concurrent private func fetchResultFromHistory(for searchText: String) async -> [QuickSearchResult] {
        do {
            let predict: Predicate<BrowserHistoryEntry>? = #Predicate { item in item.url.localizedStandardContains(searchText) || item.title.localizedStandardContains(searchText) }
            let result = try await fetchHistoryWithPredictUseCase(
                where: predict,
                batchSize: 5
            )

            return result.map { item in
                return .init(
                    type: .history,
                    title: item.title,
                    subtitle: item.url
                )
            }
        } catch {
            return []
        }
    }

    private func fetchResultFromTabs(for searchText: String) async -> [QuickSearchResult] {
        let matchedTabs = tabManager.tabs.filter {
            return $0.displayTitle.localizedCaseInsensitiveContains(searchText) || $0.displayURL.localizedCaseInsensitiveContains(searchText)
        }

        return matchedTabs.prefix(3).map {
            QuickSearchResult(
                type: .openTab,
                title: $0.displayTitle,
                subtitle: $0.displayURL,
                tabID: $0.id
            )
        }
    }

    @concurrent private func fetchSuggestions(for query: String) async -> [QuickSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(AppConstants.googleSuggestURL)\(encoded)") else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return [] }

            if let json = try JSONSerialization.jsonObject(with: data) as? [Any],
               let suggestions = json[safe: 1] as? [String] {
                let suggestResults = suggestions.prefix(5).map {
                    QuickSearchResult(
                        type: .suggestion,
                        title: $0,
                        subtitle: "Search Google"
                    )
                }

                return suggestResults
            } else { return [] }
        } catch { return [] }
    }
}
