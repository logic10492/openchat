import Foundation
import GRDB

extension DatabaseManager {
    func fetchCompressionCheckpoints(conversationId: String) async throws -> [CompressionCheckpointRecord] {
        try await read { db in
            try CompressionCheckpointRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("sourceEndSortOrder").asc)
                .fetchAll(db)
        }
    }

    func fetchLatestCompressionCheckpoint(conversationId: String) async throws -> CompressionCheckpointRecord? {
        try await read { db in
            try CompressionCheckpointRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("sourceEndSortOrder").desc, Column("createdAt").desc)
                .fetchOne(db)
        }
    }

    func saveCompressionCheckpoint(_ checkpoint: CompressionCheckpointRecord) async throws {
        try await write { db in
            try checkpoint.save(db)
        }
    }

    func deleteCompressionCheckpoints(
        conversationId: String,
        sourceEndAtOrAfter sortOrder: Int
    ) async throws {
        try await write { db in
            try CompressionCheckpointRecord
                .filter(Column("conversationId") == conversationId && Column("sourceEndSortOrder") >= sortOrder)
                .deleteAll(db)
        }
    }

    func fetchMessages(
        conversationId: String,
        sortOrderFrom start: Int,
        sortOrderThrough end: Int
    ) async throws -> [MessageRecord] {
        try await read { db in
            try MessageRecord
                .filter(Column("conversationId") == conversationId)
                .filter(Column("sortOrder") >= start && Column("sortOrder") <= end)
                .order(Column("sortOrder").asc)
                .fetchAll(db)
        }
    }
}
