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
    var reasoningContent: String?
    var stageId: String? = nil
    var speakerKind: String? = nil
    var speakerId: String? = nil
    var speakerName: String? = nil

    static let conversation = belongsTo(ConversationRecord.self)
    static let stage = belongsTo(StageRecord.self)

    var chatMessage: ChatMessage {
        ChatMessage(role: role, content: content)
    }

    var isSystemMessage: Bool {
        role == "system"
    }

    var speakerKindValue: MessageSpeakerKind? {
        guard let speakerKind else { return nil }
        return MessageSpeakerKind(rawValue: speakerKind)
    }
}
