import Foundation
import GRDB

struct WorldBookVectorStore: Sendable {
    private let databaseManager: DatabaseManager
    private let embeddingDimension = EmbeddingService.embeddingDimension

    init(databaseManager: DatabaseManager) {
        self.databaseManager = databaseManager
    }

    func upsert(entryId: String, embedding: [Float]) async throws {
        try validateDimension(embedding)
        let blob = embeddingToBlob(embedding)
        do {
            try await databaseManager.write { db in
                try deleteEmbedding(entryId: entryId, in: db)
                try insertEmbedding(entryId: entryId, blob: blob, in: db)
            }
        } catch let error as WorldBookError {
            throw error
        } catch {
            throw WorldBookError.vectorStoreError(underlying: error)
        }
    }

    func upsert(
        entryId: String,
        embedding: [Float],
        meta: WorldBookEntryEmbeddingMetaRecord
    ) async throws {
        try validateDimension(embedding)
        let blob = embeddingToBlob(embedding)
        do {
            try await databaseManager.write { db in
                try deleteEmbedding(entryId: entryId, in: db)
                try insertEmbedding(entryId: entryId, blob: blob, in: db)
                try meta.save(db)
            }
        } catch let error as WorldBookError {
            throw error
        } catch {
            throw WorldBookError.vectorStoreError(underlying: error)
        }
    }

    func search(
        query: [Float],
        worldBookId: String,
        limit: Int
    ) async throws -> [(entryId: String, distance: Float)] {
        try validateDimension(query)
        let blob = embeddingToBlob(query)
        do {
            return try await databaseManager.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT wbe.entry_id, wbe.distance
                    FROM world_book_entry_embedding wbe
                    WHERE wbe.entry_id IN (
                        SELECT id FROM world_book_entry
                        WHERE worldBookId = ? AND isEnabled = 1
                    )
                    AND wbe.embedding MATCH ?
                    AND wbe.k = ?
                    ORDER BY wbe.distance
                    """, arguments: [worldBookId, blob, limit])
                return rows.map { row in
                    (entryId: row["entry_id"] as String, distance: row["distance"] as Float)
                }
            }
        } catch let error as WorldBookError {
            throw error
        } catch {
            throw WorldBookError.vectorStoreError(underlying: error)
        }
    }

    func delete(entryId: String) async throws {
        do {
            try await databaseManager.write { db in
                try deleteEmbedding(entryId: entryId, in: db)
                _ = try WorldBookEntryEmbeddingMetaRecord.deleteOne(db, key: entryId)
            }
        } catch {
            throw WorldBookError.vectorStoreError(underlying: error)
        }
    }

    func deleteAll(worldBookId: String) async throws {
        do {
            try await databaseManager.write { db in
                try databaseManager.deleteWorldBookEntryEmbeddings(worldBookId: worldBookId, in: db)
            }
        } catch {
            throw WorldBookError.vectorStoreError(underlying: error)
        }
    }

    private func validateDimension(_ embedding: [Float]) throws {
        guard embedding.count == embeddingDimension else {
            throw WorldBookError.vectorStoreError(
                underlying: WorldBookVectorStoreValidationError.invalidDimension(
                    expected: embeddingDimension,
                    actual: embedding.count
                )
            )
        }
    }

    private func insertEmbedding(entryId: String, blob: Data, in db: Database) throws {
        try db.execute(
            sql: "INSERT INTO world_book_entry_embedding(entry_id, embedding) VALUES (?, ?)",
            arguments: [entryId, blob]
        )
    }

    private func deleteEmbedding(entryId: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM world_book_entry_embedding WHERE entry_id = ?",
            arguments: [entryId]
        )
    }

    private func embeddingToBlob(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
}

private enum WorldBookVectorStoreValidationError: LocalizedError, Sendable {
    case invalidDimension(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidDimension(let expected, let actual):
            "Invalid world book embedding dimension: expected \(expected), got \(actual)"
        }
    }
}
