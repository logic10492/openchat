import Foundation
import GRDB

struct WorldBookRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "world_book"

    var id: String
    var name: String
    var description: String?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date
}
