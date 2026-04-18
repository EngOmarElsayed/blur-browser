import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class PinnedTabStore {

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    init() {
        do {
            let schema = Schema([PinnedTabEntry.self])
            // Use a dedicated store file — default.store is already used by HistoryStore
            let storeURL = PinnedTabStore.storeURL
            print("[PinnedTabStore] Store path: \(storeURL.path)")
            let config = ModelConfiguration("PinnedTabs", url: storeURL)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = modelContainer?.mainContext
            print("[PinnedTabStore] ✅ Container created successfully")
            let count = fetchAll().count
            print("[PinnedTabStore] Existing entries: \(count)")
        } catch {
            print("[PinnedTabStore] ❌ Failed to create container: \(error)")
        }
    }

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("PinnedTabs.store")
    }

    // MARK: - Create

    func savePinnedTab(url: String, title: String, orderIndex: Int) {
        guard let context = modelContext else {
            print("[PinnedTabStore] ❌ savePinnedTab: context is nil")
            return
        }

        // Avoid duplicates by URL
        let existing = fetchAll()
        if existing.contains(where: { $0.url == url }) {
            print("[PinnedTabStore] ⚠️ savePinnedTab: duplicate url \(url), skipping")
            return
        }

        let entry = PinnedTabEntry(url: url, title: title, orderIndex: orderIndex)
        context.insert(entry)
        print("[PinnedTabStore] 📌 Inserted entry: \(title) (\(url))")
        save()
    }

    // MARK: - Delete

    func removePinnedTab(url: String) {
        guard let context = modelContext else { return }
        let entries = fetchAll()
        if let entry = entries.first(where: { $0.url == url }) {
            context.delete(entry)
            print("[PinnedTabStore] 🗑️ Removed entry: \(entry.title) (\(url))")
            save()
        } else {
            print("[PinnedTabStore] ⚠️ removePinnedTab: no entry found for url \(url)")
        }
    }

    func removeAll() {
        guard let context = modelContext else { return }
        do {
            try context.delete(model: PinnedTabEntry.self)
            save()
        } catch {
            print("[PinnedTabStore] Failed to remove all: \(error)")
        }
    }

    // MARK: - Update

    func updateOrder(tabs: [(url: String, orderIndex: Int)]) {
        let entries = fetchAll()
        for (url, newIndex) in tabs {
            if let entry = entries.first(where: { $0.url == url }) {
                entry.orderIndex = newIndex
            }
        }
        save()
    }

    // MARK: - Fetch

    func fetchAll() -> [PinnedTabEntry] {
        guard let context = modelContext else { return [] }
        let descriptor = FetchDescriptor<PinnedTabEntry>(
            sortBy: [SortDescriptor(\.orderIndex)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("[PinnedTabStore] Failed to fetch: \(error)")
            return []
        }
    }

    // MARK: - Private

    private func save() {
        do {
            try modelContext?.save()
            let count = fetchAll().count
            print("[PinnedTabStore] ✅ Saved successfully. Total entries: \(count)")
        } catch {
            print("[PinnedTabStore] ❌ Failed to save: \(error)")
        }
    }
}
