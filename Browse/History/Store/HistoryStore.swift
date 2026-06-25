import Foundation
import SwiftData

final class HistoryStore {
    private var modelContainer: ModelContainer?
    private var modelContext: ModelContext?

    var entries: [BrowserHistoryEntry] = []

    init() { initManger() }

    func initManger() {
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

    // MARK: - Grouping

    struct GroupedHistory: Identifiable {
        let id: String
        let label: String
        let entries: [BrowserHistoryEntry]
    }

    var groupedEntries: [GroupedHistory] {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let last7Days = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        let last30Days = calendar.date(byAdding: .day, value: -30, to: startOfToday)!

        var groups: [(String, String, [BrowserHistoryEntry])] = [
            ("today", "Today", []),
            ("yesterday", "Yesterday", []),
            ("last7", "Last 7 Days", []),
            ("last30", "Last 30 Days", []),
            ("older", "Older", []),
        ]

        for entry in entries {
            if entry.timestamp >= startOfToday {
                groups[0].2.append(entry)
            } else if entry.timestamp >= startOfYesterday {
                groups[1].2.append(entry)
            } else if entry.timestamp >= last7Days {
                groups[2].2.append(entry)
            } else if entry.timestamp >= last30Days {
                groups[3].2.append(entry)
            } else {
                groups[4].2.append(entry)
            }
        }

        return groups
            .filter { !$0.2.isEmpty }
            .map { GroupedHistory(id: $0.0, label: $0.1, entries: $0.2) }
    }
}

// MARK: - HistoryStoreProtocol
extension HistoryStore: HistoryStoreProtocol {
    /// Distinct hosts visited since `date`, lowercased. Used by the privacy
    /// report widget — combined with ITP records to compute the "% of sites
    /// that contacted trackers" denominator.
    func distinctHosts(since date: Date) -> Set<String> {
        guard let ctx = modelContext else { return [] }
        let descriptor = FetchDescriptor<BrowserHistoryEntry>(
            predicate: #Predicate { $0.timestamp >= date }
        )
        let recentEntries = (try? ctx.fetch(descriptor)) ?? []
        return Set(recentEntries.compactMap { entry -> String? in
            URL(string: entry.url)?.host?.lowercased()
        })
    }

    /// Convenience over `distinctHosts(since:)` — number of unique hosts.
    func distinctHostsCount(since date: Date) -> Int {
        distinctHosts(since: date).count
    }

    private func fetchEntries() {
        guard let ctx = modelContext else { return }
        var descriptor = FetchDescriptor<BrowserHistoryEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        entries = (try? ctx.fetch(descriptor)) ?? []
    }
}
