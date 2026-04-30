import Foundation
import GRDB

struct CompressionCheckpointRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "conversation_compression_checkpoint"

    var id: String
    var conversationId: String
    var parentCheckpointId: String?
    var sourceStartSortOrder: Int
    var sourceEndSortOrder: Int
    var sourceHash: String
    var summary: String
    var summaryTokenCount: Int
    var endpointId: String?
    var modelName: String
    var modelMaxContextTokens: Int
    var effectiveCompactWindowTokens: Int
    var autoCompactTokenLimit: Int
    var createdAt: Date

    static let conversation = belongsTo(ConversationRecord.self)
}
