import Foundation
import GRDB

extension DatabaseManager {
    func fetchMemories(characterCardId: String) async throws -> [MemoryEntryRecord] {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchMemories(characterCardId: String, type: MemoryType) async throws -> [MemoryEntryRecord] {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .filter(Column("memoryType") == type.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    func fetchRecentMemories(
        characterCardId: String,
        limit: Int
    ) async throws -> [MemoryEntryRecord] {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchMemoryCount(characterCardId: String) async throws -> Int {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .fetchCount(db)
        }
    }

    func hasMemoriesForConversation(conversationId: String) async throws -> Bool {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("sourceConversationId") == conversationId)
                .fetchCount(db) > 0
        }
    }

    func latestMemoryDate(conversationId: String) async throws -> Date? {
        try await read { db in
            try MemoryEntryRecord
                .filter(Column("sourceConversationId") == conversationId)
                .select(max(Column("createdAt")))
                .asRequest(of: Date?.self)
                .fetchOne(db) ?? nil
        }
    }

    func saveMemory(_ memory: MemoryEntryRecord) async throws {
        try await write { db in
            try memory.save(db)
        }
    }

    func deleteMemory(id: String) async throws {
        try await write { db in
            try db.execute(
                sql: "DELETE FROM memory_embedding WHERE entry_id = ?",
                arguments: [id]
            )
            _ = try MemoryEntryRecord.deleteOne(db, key: id)
        }
    }

    func deleteAllMemories(characterCardId: String) async throws {
        try await write { db in
            try db.execute(sql: """
                DELETE FROM memory_embedding
                WHERE entry_id IN (
                    SELECT id FROM memory_entry WHERE characterCardId = ?
                )
                """, arguments: [characterCardId])
            _ = try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .deleteAll(db)
        }
    }

    func fetchMemories(ids: [String]) async throws -> [MemoryEntryRecord] {
        guard !ids.isEmpty else { return [] }
        return try await read { db in
            try MemoryEntryRecord
                .filter(ids.contains(Column("id")))
                .fetchAll(db)
        }
    }
}
