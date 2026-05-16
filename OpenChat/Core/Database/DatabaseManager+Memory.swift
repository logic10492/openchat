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

    func fetchRecentHighValueMemories(
        characterCardId: String,
        limit: Int
    ) async throws -> [MemoryEntryRecord] {
        guard limit > 0 else { return [] }
        return try await read { db in
            try MemoryEntryRecord
                .filter(Column("characterCardId") == characterCardId)
                .filter(
                    [MemoryType.relationship.rawValue, MemoryType.summary.rawValue].contains(Column("memoryType")) ||
                        Column("importance") >= 70
                )
                .order(
                    sql: """
                    CASE
                      WHEN memoryType = ? THEN 0
                      WHEN memoryType = ? THEN 1
                      ELSE 2
                    END,
                    importance DESC,
                    createdAt DESC
                    """,
                    arguments: [MemoryType.relationship.rawValue, MemoryType.summary.rawValue]
                )
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

    // MARK: - Memory Provenance

    func saveMemoryProvenance(_ provenance: MemoryEntryProvenanceRecord) async throws {
        try await write { db in
            try provenance.save(db)
        }
    }

    func fetchMemoryProvenance(memoryEntryId: String) async throws -> MemoryEntryProvenanceRecord? {
        try await read { db in
            try MemoryEntryProvenanceRecord.fetchOne(db, key: memoryEntryId)
        }
    }

    func fetchMemoryProvenances(memoryEntryIds: [String]) async throws -> [MemoryEntryProvenanceRecord] {
        guard !memoryEntryIds.isEmpty else { return [] }
        return try await read { db in
            try MemoryEntryProvenanceRecord
                .filter(memoryEntryIds.contains(Column("memoryEntryId")))
                .fetchAll(db)
        }
    }

    func deleteMemoryProvenance(memoryEntryId: String) async throws {
        try await write { db in
            _ = try MemoryEntryProvenanceRecord.deleteOne(db, key: memoryEntryId)
        }
    }
}
