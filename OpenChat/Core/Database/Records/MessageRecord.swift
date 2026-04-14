import Foundation
import GRDB

struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "message"

    var id: String
    var conversationId: String
    var role: String
    var content: String
    var tokenCount: Int?
    var isCompressed: Bool
    var originalContent: String?
    var sortOrder: Int
    var createdAt: Date

    static let conversation = belongsTo(ConversationRecord.self)

    var chatMessage: ChatMessage {
        ChatMessage(role: role, content: content)
    }

    var isSystemMessage: Bool {
        role == "system"
    }
}
