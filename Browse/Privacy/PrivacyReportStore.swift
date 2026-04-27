import Foundation
import Observation

/// Owns the live `PrivacyReportSnapshot` driving the new-tab widget.
///
/// Single instance shared across windows — the SPI's data is global to the
/// `WKWebsiteDataStore.default()` instance, so per-window stores would all
/// produce identical snapshots. Keeping it shared also means windows can
/// observe the same `@Observable` and update simultaneously when the snapshot
/// refreshes.
@Observable
@MainActor
final class PrivacyReportStore {

    static let shared = PrivacyReportStore()

    /// Most recent snapshot. Views render from this directly.
    private(set) var snapshot: PrivacyReportSnapshot = .empty

    /// True while a refresh is in flight. Lets the view show a subtle loading
    /// state instead of "0 trackers" on first paint.
    private(set) var isLoading: Bool = false

    /// Injected at startup so we can compute the % denominator from history.
    private weak var historyStore: HistoryStore?

    private init() {}

    func setHistoryStore(_ store: HistoryStore) {
        self.historyStore = store
    }

    // MARK: - Refresh

    /// Pull the latest summary from `PrivacyReportService`, filter to last 30
    /// days, **scope it to sites the user actually visited in this browser**,
    /// and publish the resulting snapshot.
    ///
    /// All four metrics are derived from the user's `HistoryStore`:
    ///   - If history is empty (last 30d) → snapshot is all zeros. We never
    ///     report on sites the user didn't visit in our browser.
    ///   - tracker count, top tracker, % — all computed only over ITP records
    ///     whose first-party domain matches a host in the user's history.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 86400)
        let historyHosts: Set<String> = historyStore?.distinctHosts(since: thirtyDaysAgo) ?? []

        // No browsing in this browser → no privacy report at all. The view
        // observes `hasBrowsingHistory` and hides itself entirely.
        guard !historyHosts.isEmpty else {
            snapshot = PrivacyReportSnapshot(
                hasBrowsingHistory: false,
                trackerCount: 0,
                pctSitesContacted: 0,
                topTracker: nil,
                lastUpdated: Date()
            )
            return
        }

        let records = await PrivacyReportService.fetchSummary()

        /// ITP first-party domains are registrable (eTLD+1, e.g. "google.com")
        /// while history hosts can be subdomains ("mail.google.com"). Match a
        /// history host to an ITP first-party with suffix comparison.
        func historyHostsMatching(_ itpDomain: String) -> Set<String> {
            let d = itpDomain.lowercased()
            return historyHosts.filter { $0 == d || $0.hasSuffix("." + d) }
        }

        struct Aggregated {
            let trackerDomain: String
            let matchingHosts: Set<String>  // history hosts where this tracker appeared
        }

        // For each tracker, find which of YOUR history hosts it actually
        // appeared on within the last 30 days. Drop trackers with no matches.
        let aggregated: [Aggregated] = records.compactMap { record in
            var hits = Set<String>()
            for fp in record.firstParties where fp.timeLastUpdated >= thirtyDaysAgo {
                hits.formUnion(historyHostsMatching(fp.firstPartyDomain))
            }
            return hits.isEmpty
                ? nil
                : Aggregated(trackerDomain: record.thirdPartyDomain, matchingHosts: hits)
        }

        let trackerCount = aggregated.count

        let topTracker: TopTracker? = aggregated
            .max { $0.matchingHosts.count < $1.matchingHosts.count }
            .map { TopTracker(domain: $0.trackerDomain, acrossSitesCount: $0.matchingHosts.count) }

        // % = (history hosts that had any tracker) / (all history hosts) × 100
        // Bounded by construction since the numerator is a subset of the denom.
        let hostsWithTrackers = Set(aggregated.flatMap(\.matchingHosts))
        let pct = Int((Double(hostsWithTrackers.count) / Double(historyHosts.count) * 100).rounded())

        snapshot = PrivacyReportSnapshot(
            hasBrowsingHistory: true,
            trackerCount: trackerCount,
            pctSitesContacted: pct,
            topTracker: topTracker,
            lastUpdated: Date()
        )
    }

    /// Wipe ITP data and recompute. Backs the Settings → Privacy → Clear button.
    func clearAndRefresh() async {
        await PrivacyReportService.clearAll()
        await refresh()
    }
}
