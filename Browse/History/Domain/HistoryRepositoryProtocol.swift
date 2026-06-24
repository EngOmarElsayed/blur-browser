//
//  HistoryRepositoryProtocol.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 23/06/2026.
//

import Foundation
import FactoryKit
import SwiftData

// MARK: - HistoryRepositoryProtocol
protocol HistoryRepositoryProtocol {
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

// MARK: - HistoryRepository
struct HistoryRepository {
    @Injected(\.historyLocalDataStore) private var historyLocalDataStore: HistoryLocalDataStoreProtocol
}

// MARK: - HistoryRepositoryProtocol Implementation
extension HistoryRepository: HistoryRepositoryProtocol {
    func fetchItems(
        where predict: Predicate<BrowserHistoryEntry>?,
        sortBy: (KeyPath<BrowserHistoryEntry, String> & Sendable)?,
        order: SortOrder?,
        batchSize: Int
    ) async throws -> [BrowserHistoryEntry] {
        var descriptor = FetchDescriptor<BrowserHistoryEntry>()
        if let predict {
            descriptor.predicate = predict
        }

        if let sortBy {
            descriptor.sortBy = [SortDescriptor(sortBy, order: order ?? .forward)]
        }

        return try await historyLocalDataStore.fetch(with: descriptor, batchSize: batchSize)
    }

    func addItem(title: String, url: URL, faviconUrl: URL?) async throws {
        try await historyLocalDataStore
            .add(
                title: title,
                url: url,
                faviconUrl: faviconUrl
            )
    }

    func deleteAllItems() async throws {
        try await historyLocalDataStore.deleteItems(where: nil)
    }

    func deleteItems(where predict: Predicate<BrowserHistoryEntry>) async throws {
        try await historyLocalDataStore.deleteItems(where: predict)
    }
}
