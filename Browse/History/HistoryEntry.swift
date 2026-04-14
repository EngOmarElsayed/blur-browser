import Foundation
import SwiftData

@Model
final class HistoryEntry {
    var url: String
    var title: String
    var timestamp: Date
    var faviconURL: String?

    init(url: String, title: String, timestamp: Date = .now, faviconURL: String? = nil) {
        self.url = url
        self.title = title
        self.timestamp = timestamp
        self.faviconURL = faviconURL
    }
}
