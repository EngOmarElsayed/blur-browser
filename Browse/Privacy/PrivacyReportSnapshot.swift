import Foundation

/// Immutable snapshot of the four widget metrics, scoped to the last 30 days.
/// Computed by `PrivacyReportStore.refresh()` from raw `_WKResourceLoad...`
/// records returned by `PrivacyReportService.fetchSummary()`.
struct PrivacyReportSnapshot: Equatable {
    /// True iff the user has at least one history entry in the last 30 days
    /// of using THIS browser. The widget is hidden entirely when false —
    /// we don't show a report on a user who hasn't browsed yet.
    let hasBrowsingHistory: Bool

    /// Distinct trackers observed on at least one site in the last 30 days.
    let trackerCount: Int

    /// % of visited sites where at least one tracker was observed. `nil` when
    /// we don't have enough history yet to compute a denominator.
    let pctSitesContacted: Int?

    /// The tracker that appeared on the most distinct first parties.
    let topTracker: TopTracker?

    /// When this snapshot was computed.
    let lastUpdated: Date

    static let empty = PrivacyReportSnapshot(
        hasBrowsingHistory: false,
        trackerCount: 0,
        pctSitesContacted: nil,
        topTracker: nil,
        lastUpdated: .distantPast
    )
}

struct TopTracker: Equatable {
    let domain: String
    /// Number of distinct first-party sites this tracker appeared on (last 30d).
    let acrossSitesCount: Int
}

// MARK: - Service-level types (raw SPI translation)

/// Swift-typed mirror of `_WKResourceLoadStatisticsThirdParty`. Produced by
/// `PrivacyReportService.fetchSummary()` so the rest of the app never has to
/// touch KVC or Objective-C runtime calls directly.
struct ThirdPartyRecord: Equatable {
    let thirdPartyDomain: String
    let firstParties: [FirstPartyRecord]
}

struct FirstPartyRecord: Equatable {
    let firstPartyDomain: String
    let timeLastUpdated: Date
}
