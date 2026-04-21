import Foundation
import SwiftData

enum DownloadStatus: String, Codable {
    case inProgress
    case paused
    case completed
    case failed
    case cancelled
}

@Model
final class DownloadItem {
    var id: UUID = UUID()
    var fileName: String
    var localURL: String
    var sourceURL: String
    var totalBytes: Int64?
    var completedBytes: Int64 = 0
    /// Stored as `DownloadStatus.rawValue`
    var statusRaw: String
    var startedAt: Date = Date()
    var completedAt: Date?
    /// Saved by pause — used to resume a WKDownload via `webView.resumeDownload(fromResumeData:)`
    var resumeData: Data?

    init(
        id: UUID = UUID(),
        fileName: String,
        localURL: String,
        sourceURL: String,
        totalBytes: Int64? = nil,
        completedBytes: Int64 = 0,
        status: DownloadStatus = .inProgress,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.localURL = localURL
        self.sourceURL = sourceURL
        self.totalBytes = totalBytes
        self.completedBytes = completedBytes
        self.statusRaw = status.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    var status: DownloadStatus {
        get { DownloadStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var localFileURL: URL? { URL(fileURLWithPath: localURL) }
    var sourceFileURL: URL? { URL(string: sourceURL) }

    /// Progress as a fraction 0...1, or nil when totalBytes is unknown.
    var fractionComplete: Double? {
        guard let total = totalBytes, total > 0 else { return nil }
        return min(1.0, Double(completedBytes) / Double(total))
    }
}
