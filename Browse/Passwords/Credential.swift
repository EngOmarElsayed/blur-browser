import Foundation

struct Credential: Hashable, Identifiable, Sendable {
    let id: UUID
    let site: String        // eTLD+1 from SiteIdentity
    let username: String
    let password: String
    let createdAt: Date
    let updatedAt: Date

    init(id: UUID = UUID(),
         site: String,
         username: String,
         password: String,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.id = id
        self.site = site
        self.username = username
        self.password = password
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
