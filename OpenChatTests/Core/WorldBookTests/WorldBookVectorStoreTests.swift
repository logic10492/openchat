import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("WorldBookVectorStore")
struct WorldBookVectorStoreTests {
    @Test func test_upsert_saves_vector_for_world_book_search() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let entry = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "entry-a",
            title: "Silverwood"
        )
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)

        try await store.upsert(entryId: entry.id, embedding: makeEmbedding(firstValue: 0.8))

        let vectorCount = try await vectorRowCount(entryId: entry.id, in: manager)
        let results = try await store.search(
            query: makeEmbedding(firstValue: 1.0),
            worldBookId: worldBook.id,
            limit: 1
        )

        #expect(vectorCount == 1)
        #expect(results.map(\.entryId) == [entry.id])
    }

    @Test func test_search_limits_knn_to_requested_world_book_before_topK() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let worldBookA = TestHelpers.makeWorldBook(id: "world-a")
        let worldBookB = TestHelpers.makeWorldBook(id: "world-b")
        let entryAFirst = TestHelpers.makeWorldBookEntry(worldBookId: worldBookA.id, id: "a-1")
        let entryASecond = TestHelpers.makeWorldBookEntry(worldBookId: worldBookA.id, id: "a-2")
        let entryBFirst = TestHelpers.makeWorldBookEntry(worldBookId: worldBookB.id, id: "b-1")
        let entryBSecond = TestHelpers.makeWorldBookEntry(worldBookId: worldBookB.id, id: "b-2")
        try await insertWorldBooks(
            [worldBookA, worldBookB],
            entries: [entryAFirst, entryASecond, entryBFirst, entryBSecond],
            into: manager
        )

        try await store.upsert(entryId: entryAFirst.id, embedding: makeEmbedding(firstValue: 0.8))
        try await store.upsert(entryId: entryASecond.id, embedding: makeEmbedding(firstValue: 0.7))
        try await store.upsert(entryId: entryBFirst.id, embedding: makeEmbedding(firstValue: 1.0))
        try await store.upsert(entryId: entryBSecond.id, embedding: makeEmbedding(firstValue: 0.99))

        let results = try await store.search(
            query: makeEmbedding(firstValue: 1.0),
            worldBookId: worldBookA.id,
            limit: 2
        )

        #expect(results.map(\.entryId) == [entryAFirst.id, entryASecond.id])
        #expect(results.allSatisfy { $0.distance.isFinite })
        #expect(results[0].distance <= results[1].distance)
    }

    @Test func test_search_ignores_disabled_entries() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let enabled = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "enabled-entry")
        var disabled = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "disabled-entry")
        disabled.isEnabled = false
        try await insertWorldBooks([worldBook], entries: [enabled, disabled], into: manager)

        try await store.upsert(entryId: enabled.id, embedding: makeEmbedding(firstValue: 0.8))
        try await store.upsert(entryId: disabled.id, embedding: makeEmbedding(firstValue: 1.0))

        let results = try await store.search(
            query: makeEmbedding(firstValue: 1.0),
            worldBookId: worldBook.id,
            limit: 2
        )

        #expect(results.map(\.entryId) == [enabled.id])
    }

    @Test func test_delete_removes_vector_row() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-a")
        let meta = WorldBookEntryEmbeddingMetaRecord(
            entryId: entry.id,
            contentHash: "hash-a",
            embeddingModel: "MultilingualE5Small",
            embeddingDimension: EmbeddingService.embeddingDimension,
            status: WorldBookEmbeddingStatus.indexed.rawValue,
            embeddedAt: Date(),
            lastAttemptAt: Date(),
            lastError: nil,
            updatedAt: Date()
        )
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)
        try await manager.write { db in
            try meta.insert(db)
        }
        try await store.upsert(entryId: entry.id, embedding: makeEmbedding(firstValue: 0.8))

        try await store.delete(entryId: entry.id)

        let vectorCount = try await vectorRowCount(entryId: entry.id, in: manager)
        let metaCount = try await metaRowCount(entryId: entry.id, in: manager)
        #expect(vectorCount == 0)
        #expect(metaCount == 0)
    }

    @Test func test_invalid_dimension_throws_before_partial_write() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-a")
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)

        do {
            try await store.upsert(entryId: entry.id, embedding: [1, 2, 3])
            Issue.record("Expected invalid world book vector dimension to throw")
        } catch let error as WorldBookError {
            guard case .vectorStoreError = error else {
                Issue.record("Expected WorldBookError.vectorStoreError, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected WorldBookError.vectorStoreError, got \(error)")
        }

        let vectorCount = try await vectorRowCount(entryId: entry.id, in: manager)
        #expect(vectorCount == 0)
    }

    private func insertWorldBooks(
        _ worldBooks: [WorldBookRecord],
        entries: [WorldBookEntryRecord],
        into manager: DatabaseManager
    ) async throws {
        try await manager.write { db in
            for worldBook in worldBooks {
                try worldBook.insert(db)
            }
            for entry in entries {
                try entry.insert(db)
            }
        }
    }

    private func vectorRowCount(entryId: String, in manager: DatabaseManager) async throws -> Int {
        try await manager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM world_book_entry_embedding WHERE entry_id = ?",
                arguments: [entryId]
            ) ?? 0
        }
    }

    private func metaRowCount(entryId: String, in manager: DatabaseManager) async throws -> Int {
        try await manager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM world_book_entry_embedding_meta WHERE entryId = ?",
                arguments: [entryId]
            ) ?? 0
        }
    }

    private func makeEmbedding(firstValue: Float) -> [Float] {
        var embedding = Array(repeating: Float(0), count: EmbeddingService.embeddingDimension)
        embedding[0] = firstValue
        return embedding
    }
}
