//
//  HistoryRepositoryProtocol 2.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 24/06/2026.
//

import Foundation

// MARK: - HistoryRepositoryProtocol
protocol HistoryRepositoryProtocol: Sendable {
    func fetchItems(
        where predict: Predicate<BrowserHistoryEntry>?,
        sortBy: (KeyPath<BrowserHistoryEntry, String> & Sendable)?,
        order: SortOrder?,
        batchSize: Int
    ) async throws -> [BrowserHistoryEntry]

    func addItem(title: String, url: URL, faviconUrl: URL?) async throws
    func deleteAllItems() async throws
    func deleteItems(where predict: Predicate<BrowserHistoryEntry>) async throws
}
