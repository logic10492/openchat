import Foundation
import GRDB

struct VectorStore: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingDimension = EmbeddingService.embeddingDimension

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func insert(entryId: String, embedding: [Float]) async throws {
        try validateDimension(embedding)
        let blob = embeddingToBlob(embedding)
        do {
            try await databaseManager.write { db in
                try insertEmbedding(entryId: entryId, blob: blob, in: db)
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws {
        try validateDimension(embedding)
        let blob = embeddingToBlob(embedding)
        do {
            try await databaseManager.write { db in
                try entry.save(db)
                try insertEmbedding(entryId: entry.id, blob: blob, in: db)
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func search(
        query: [Float],
        characterCardId: String,
        limit: Int = 5
    ) async throws -> [(entryId: String, distance: Float)] {
        try validateDimension(query)
        let blob = embeddingToBlob(query)
        do {
            return try await databaseManager.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT me.entry_id, me.distance
                    FROM memory_embedding me
                    WHERE me.entry_id IN (
                        SELECT id FROM memory_entry WHERE characterCardId = ?
                    )
                    AND me.embedding MATCH ?
                    AND me.k = ?
                    ORDER BY me.distance
                    """, arguments: [characterCardId, blob, limit])
                return rows.map { row in
                    (entryId: row["entry_id"] as String, distance: row["distance"] as Float)
                }
            }
        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func delete(entryId: String) async throws {
        do {
            try await databaseManager.write { db in
                try db.execute(
                    sql: "DELETE FROM memory_embedding WHERE entry_id = ?",
                    arguments: [entryId]
                )
                _ = try MemoryEntryRecord.deleteOne(db, key: entryId)
            }
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    func deleteAll(characterCardId: String) async throws {
        do {
            try await databaseManager.write { db in
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
        } catch {
            throw MemoryError.vectorStoreError(underlying: error)
        }
    }

    private func validateDimension(_ embedding: [Float]) throws {
        guard embedding.count == embeddingDimension else {
            throw MemoryError.vectorStoreError(
                underlying: VectorStoreValidationError.invalidDimension(
                    expected: embeddingDimension,
                    actual: embedding.count
                )
            )
        }
    }

    private func insertEmbedding(entryId: String, blob: Data, in db: Database) throws {
        try db.execute(
            sql: "INSERT INTO memory_embedding(entry_id, embedding) VALUES (?, ?)",
            arguments: [entryId, blob]
        )
    }

    private func embeddingToBlob(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}

private enum VectorStoreValidationError: LocalizedError, Sendable {
    case invalidDimension(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidDimension(let expected, let actual):
            "Invalid embedding dimension: expected \(expected), got \(actual)"
        }
    }
}
