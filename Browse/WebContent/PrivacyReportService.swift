import WebKit
import Foundation

/// Bridge to WebKit's private resource-load-statistics SPI for the Privacy
/// Report widget.
///
/// We dispatch through an `@objc` optional protocol so missing selectors
/// no-op silently if Apple renames or removes them in a future macOS.
/// Reference: WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKWebsiteDataStorePrivate.h
@objc protocol WKWebsiteDataStoreSPI {
    /// Aggregate query — returns one record per third-party (tracker)
    /// domain WebKit's ITP has observed, with the first parties it appeared
    /// under nested inside.
    @objc(_getResourceLoadStatisticsDataSummary:)
    optional func getResourceLoadStatisticsDataSummary(
        completionHandler: @escaping ([Any]) -> Void
    )

    /// Wipe ITP's accumulated stats. Used for "Clear Privacy Report".
    @objc(_clearResourceLoadStatistics:)
    optional func clearResourceLoadStatistics(
        completionHandler: @escaping () -> Void
    )

    @objc(_setResourceLoadStatisticsEnabled:)
    optional func setResourceLoadStatisticsEnabled(_ enabled: Bool)
}

extension WKWebsiteDataStore: WKWebsiteDataStoreSPI {}

@MainActor
enum PrivacyReportService {

    /// Make sure ITP is on. Default for `.default()` data store is already
    /// `true`, but be explicit so a misconfigured environment doesn't
    /// silently produce empty reports.
    static func enableITP() {
        let store = WKWebsiteDataStore.default()
        let priv: WKWebsiteDataStoreSPI = store
        if store.responds(to: NSSelectorFromString("_setResourceLoadStatisticsEnabled:")) {
            priv.setResourceLoadStatisticsEnabled?(true)
        }
    }

    /// Pull the current ITP summary out of WebKit and translate it into Swift
    /// structs. Empty array if the SPI is unavailable or returns no data.
    /// Timestamps are decoded as Unix epoch (`Date(timeIntervalSince1970:)`).
    static func fetchSummary() async -> [ThirdPartyRecord] {
        let store = WKWebsiteDataStore.default()
        guard store.responds(to: NSSelectorFromString("_getResourceLoadStatisticsDataSummary:")) else {
            return []
        }
        let priv: WKWebsiteDataStoreSPI = store

        return await withCheckedContinuation { (continuation: CheckedContinuation<[ThirdPartyRecord], Never>) in
            priv.getResourceLoadStatisticsDataSummary? { rawRecords in
                let records = rawRecords.compactMap { item -> ThirdPartyRecord? in
                    guard let third = item as? NSObject else { return nil }
                    guard let domain = third.value(forKey: "thirdPartyDomain") as? String else { return nil }
                    let firstPartiesRaw = (third.value(forKey: "underFirstParties") as? [Any]) ?? []
                    let firstParties = firstPartiesRaw.compactMap { fp -> FirstPartyRecord? in
                        guard let obj = fp as? NSObject else { return nil }
                        guard let fpDomain = obj.value(forKey: "firstPartyDomain") as? String else { return nil }
                        let ts = (obj.value(forKey: "timeLastUpdated") as? NSNumber)?.doubleValue ?? 0
                        return FirstPartyRecord(
                            firstPartyDomain: fpDomain,
                            timeLastUpdated: Date(timeIntervalSince1970: ts)
                        )
                    }
                    return ThirdPartyRecord(thirdPartyDomain: domain, firstParties: firstParties)
                }
                continuation.resume(returning: records)
            }
        }
    }

    /// Wipe WebKit's accumulated ITP stats. Backs the "Clear Privacy Report"
    /// flow. No-op if the SPI is unavailable on this OS.
    static func clearAll() async {
        let store = WKWebsiteDataStore.default()
        guard store.responds(to: NSSelectorFromString("_clearResourceLoadStatistics:")) else { return }
        let priv: WKWebsiteDataStoreSPI = store
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            priv.clearResourceLoadStatistics? {
                continuation.resume()
            }
        }
    }
}
