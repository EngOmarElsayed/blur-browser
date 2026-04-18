import Foundation
import SwiftData

@Model
final class PinnedTabEntry {
    var id: UUID = UUID()
    var url: String
    var title: String
    var orderIndex: Int
    var dateAdded: Date = Date()

    init(id: UUID = UUID(), url: String, title: String, orderIndex: Int, dateAdded: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.orderIndex = orderIndex
        self.dateAdded = dateAdded
    }
}
