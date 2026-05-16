import Foundation
import GRDB

struct WorldBookEntryEmbeddingMetaRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "world_book_entry_embedding_meta"

    var entryId: String
    var contentHash: String
    var embeddingModel: String
    var embeddingDimension: Int
    var status: String
    var embeddedAt: Date?
    var lastAttemptAt: Date?
    var lastError: String?
    var updatedAt: Date

    static let worldBookEntry = belongsTo(
        WorldBookEntryRecord.self,
        using: ForeignKey(["entryId"])
    )

    var statusValue: WorldBookEmbeddingStatus {
        WorldBookEmbeddingStatus(rawValue: status) ?? .needsRebuild
    }
}
