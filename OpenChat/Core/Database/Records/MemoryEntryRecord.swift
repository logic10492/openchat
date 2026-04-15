import Foundation
import GRDB

struct MemoryEntryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "memory_entry"

    var id: String
    var characterCardId: String
    var sourceConversationId: String?
    var content: String
    var memoryType: String
    var importance: Int
    var createdAt: Date
    var updatedAt: Date

    static let characterCard = belongsTo(CharacterCardRecord.self)
    static let sourceConversation = belongsTo(
        ConversationRecord.self,
        using: ForeignKey(["sourceConversationId"])
    )

    var memoryTypeValue: MemoryType {
        MemoryType(rawValue: memoryType) ?? .event
    }
}
