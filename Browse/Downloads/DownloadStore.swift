import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class DownloadStore {

    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    /// In-memory mirror of the DB so SwiftUI views can observe changes.
    /// We re-fetch whenever anything mutates.
    private(set) var items: [DownloadItem] = []

    init() {
        do {
            let schema = Schema([DownloadItem.self])
            let storeURL = Self.storeURL
            let config = ModelConfiguration("Downloads", url: storeURL)
            modelContainer = try ModelContainer(for: schema, configurations: [config])
            modelContext = modelContainer?.mainContext
            refresh()
        } catch {
            print("[DownloadStore] Failed to create container: \(error)")
        }
    }

    private static var storeURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppConstants.appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Downloads.store")
    }

    // MARK: - Create

    @discardableResult
    func addDownload(
        id: UUID,
        fileName: String,
        localURL: URL,
        sourceURL: URL?,
        totalBytes: Int64?
    ) -> DownloadItem? {
        guard let context = modelContext else { return nil }
        let item = DownloadItem(
            id: id,
            fileName: fileName,
            localURL: localURL.path,
            sourceURL: sourceURL?.absoluteString ?? "",
            totalBytes: totalBytes,
            status: .inProgress
        )
        context.insert(item)
        save()
        refresh()
        return item
    }

    // MARK: - Update

    func updateProgress(id: UUID, completed: Int64, total: Int64?) {
        guard let item = findItem(id: id) else { return }
        item.completedBytes = completed
        if let total, total > 0 { item.totalBytes = total }
        save()
        refresh()
    }

    func markCompleted(id: UUID) {
        guard let item = findItem(id: id) else { return }
        item.status = .completed
        item.completedAt = Date()
        if let total = item.totalBytes { item.completedBytes = total }
        save()
        refresh()
    }

    func markFailed(id: UUID) {
        guard let item = findItem(id: id) else { return }
        item.status = .failed
        item.completedAt = Date()
        save()
        refresh()
    }

    func markCancelled(id: UUID) {
        guard let item = findItem(id: id) else { return }
        item.status = .cancelled
        item.completedAt = Date()
        save()
        refresh()
    }

    func markPaused(id: UUID, resumeData: Data?) {
        guard let item = findItem(id: id) else { return }
        item.status = .paused
        item.resumeData = resumeData
        save()
        refresh()
    }

    func markResumed(id: UUID) {
        guard let item = findItem(id: id) else { return }
        item.status = .inProgress
        item.resumeData = nil
        save()
        refresh()
    }

    // MARK: - Delete

    func removeDownload(id: UUID) {
        guard let context = modelContext, let item = findItem(id: id) else { return }
        context.delete(item)
        save()
        refresh()
    }

    func removeAll() {
        guard let context = modelContext else { return }
        do {
            try context.delete(model: DownloadItem.self)
            save()
            refresh()
        } catch {
            print("[DownloadStore] Failed to remove all: \(error)")
        }
    }

    // MARK: - Query

    var activeDownloads: [DownloadItem] {
        items.filter { $0.status == .inProgress }
    }

    func search(_ query: String) -> [DownloadItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.fileName.lowercased().contains(q) }
    }

    // MARK: - Private

    private func refresh() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<DownloadItem>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        do {
            items = try context.fetch(descriptor)
        } catch {
            print("[DownloadStore] Fetch failed: \(error)")
        }
    }

    private func findItem(id: UUID) -> DownloadItem? {
        items.first(where: { $0.id == id })
    }

    private func save() {
        do { try modelContext?.save() } catch {
            print("[DownloadStore] Save failed: \(error)")
        }
    }
}
