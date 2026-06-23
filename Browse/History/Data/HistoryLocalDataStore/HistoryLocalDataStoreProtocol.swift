//
//  HistoryLocalDataStoreProtocol.swift
//  Blur-Browser
//
//  Created by Omar Elsayed on 23/06/2026.
//

import Foundation
import SwiftData

// MARK: - HistoryLocalDataStoreProtocol
@HistoryLocalDataStoreActor
protocol HistoryLocalDataStoreProtocol: Sendable {
    func add(title: String, url: URL, faviconUrl: URL?) throws
    func deleteItems(where predict: Predicate<BrowserHistoryEntry>?) throws

    func fetch(
        with descriptor: FetchDescriptor<BrowserHistoryEntry>,
        batchSize: Int
    ) throws -> [BrowserHistoryEntry]
    func fetch<Key: Hashable>(
        with descriptor: FetchDescriptor<BrowserHistoryEntry>,
        groupBy value: (BrowserHistoryEntry) -> Key,
        batchSize: Int
    ) throws -> [Key: [BrowserHistoryEntry]]
}

// MARK: - HistoryLocalDataStore
@HistoryLocalDataStoreActor
final class HistoryLocalDataStore {
    static let shared: HistoryLocalDataStoreProtocol = HistoryLocalDataStore()
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    private init() { initManger() }
    private func initManger() {
        do {
            let schema = Schema([BrowserHistoryEntry.self])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            let modelContainer = try ModelContainer(for: schema, configurations: [config])
            let modelContext = ModelContext(modelContainer)

            self.modelContainer = modelContainer
            self.modelContext = modelContext
        } catch {
            print("Failed to create HistoryStore: \(error)")
        }
    }
}

// MARK: - HistoryLocalDataStoreProtocol Impl
extension HistoryLocalDataStore: HistoryLocalDataStoreProtocol {
    func fetch(
        with descriptor: FetchDescriptor<BrowserHistoryEntry>,
        batchSize: Int
    ) throws -> [BrowserHistoryEntry] {
        guard let context = modelContext else { throw HistoryLocalDataStoreError.modelContextIsNotFound }
        return Array(try context.fetch(descriptor, batchSize: batchSize))
    }

    func fetch<Key: Hashable>(
        with descriptor: FetchDescriptor<BrowserHistoryEntry>,
        groupBy value: (BrowserHistoryEntry) -> Key,
        batchSize: Int
    ) throws -> [Key: [BrowserHistoryEntry]] {
        let result = try fetch(with: descriptor, batchSize: batchSize)
        return Dictionary(grouping: result, by: value)
    }

    func add(title: String, url: URL, faviconUrl: URL?) throws {
        guard let context = modelContext else { throw HistoryLocalDataStoreError.modelContextIsNotFound }
        let entry = BrowserHistoryEntry(
            url: url.absoluteString,
            title: title,
            faviconURL: faviconUrl?.absoluteString
        )

        context.insert(entry)
        try context.save()
    }

    /// Note: if you passed nil to this function all the data will be deleted
    func deleteItems(where predict: Predicate<BrowserHistoryEntry>?) throws {
        guard let context = modelContext else { throw HistoryLocalDataStoreError.modelContextIsNotFound }
        try context.delete(model: BrowserHistoryEntry.self, where: predict, includeSubclasses: true)
        try context.save()
    }
}
