import Foundation
import GRDB

struct VectorStore: Sendable {
    private let databaseManager: DatabaseManager

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func insert(entryId: String, embedding: [Float]) async throws {
        let blob = embeddingToBlob(embedding)
        try await databaseManager.write { db in
            try db.execute(
                sql: "INSERT INTO memory_embedding(entry_id, embedding) VALUES (?, ?)",
                arguments: [entryId, blob]
            )
        }
    }

    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws {
        try await insert(entryId: entry.id, embedding: embedding)
    }

    func search(
        query: [Float],
        characterCardId: String,
        limit: Int = 5
    ) async throws -> [(entryId: String, distance: Float)] {
        let blob = embeddingToBlob(query)
        return try await databaseManager.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT me.entry_id, me.distance
                FROM memory_embedding me
                INNER JOIN memory_entry m ON m.id = me.entry_id
                WHERE m.characterCardId = ?
                AND me.embedding MATCH ?
                ORDER BY me.distance
                LIMIT ?
                """, arguments: [characterCardId, blob, limit])
            return rows.map { row in
                (entryId: row["entry_id"] as String, distance: row["distance"] as Float)
            }
        }
    }

    func delete(entryId: String) async throws {
        try await databaseManager.write { db in
            try db.execute(
                sql: "DELETE FROM memory_embedding WHERE entry_id = ?",
                arguments: [entryId]
            )
        }
    }

    func deleteAll(characterCardId: String) async throws {
        try await databaseManager.write { db in
            try db.execute(sql: """
                DELETE FROM memory_embedding
                WHERE entry_id IN (
                    SELECT id FROM memory_entry WHERE characterCardId = ?
                )
                """, arguments: [characterCardId])
        }
    }

    private func embeddingToBlob(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}
