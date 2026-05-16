import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("DatabaseManager world book embedding cleanup")
struct DatabaseManagerWorldBookTests {
    @Test func test_delete_world_book_entry_removes_embedding_and_meta() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook(id: "world-delete-entry")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-delete")
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)
        try await insertEmbedding(entryId: entry.id, into: manager)

        try await manager.deleteWorldBookEntry(id: entry.id)

        #expect(try await entryCount(id: entry.id, in: manager) == 0)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 0)
        #expect(try await metaRowCount(entryId: entry.id, in: manager) == 0)
    }

    @Test func test_delete_world_book_removes_all_entry_embeddings_and_meta() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook(id: "world-delete")
        let keptWorldBook = TestHelpers.makeWorldBook(id: "world-keep")
        let deletedEntries = [
            TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-delete-a"),
            TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-delete-b"),
        ]
        let keptEntry = TestHelpers.makeWorldBookEntry(worldBookId: keptWorldBook.id, id: "entry-keep")
        try await insertWorldBooks([worldBook, keptWorldBook], entries: deletedEntries + [keptEntry], into: manager)
        for entry in deletedEntries + [keptEntry] {
            try await insertEmbedding(entryId: entry.id, into: manager)
        }

        try await manager.deleteWorldBook(id: worldBook.id)

        for entry in deletedEntries {
            #expect(try await entryCount(id: entry.id, in: manager) == 0)
            #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 0)
            #expect(try await metaRowCount(entryId: entry.id, in: manager) == 0)
        }
        #expect(try await entryCount(id: keptEntry.id, in: manager) == 1)
        #expect(try await vectorRowCount(entryId: keptEntry.id, in: manager) == 1)
        #expect(try await metaRowCount(entryId: keptEntry.id, in: manager) == 1)
    }

    @Test func test_erase_all_data_removes_world_book_embeddings() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook(id: "world-erase")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-erase")
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)
        try await insertEmbedding(entryId: entry.id, into: manager)

        try await manager.eraseAllData(preserveEndpoints: false)

        #expect(try await entryCount(id: entry.id, in: manager) == 0)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 0)
        #expect(try await metaRowCount(entryId: entry.id, in: manager) == 0)
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

    private func insertEmbedding(entryId: String, into manager: DatabaseManager) async throws {
        let store = WorldBookVectorStore(databaseManager: manager)
        try await store.upsert(
            entryId: entryId,
            embedding: makeEmbedding(),
            meta: WorldBookEntryEmbeddingMetaRecord(
                entryId: entryId,
                contentHash: "hash-\(entryId)",
                embeddingModel: EmbeddingService.embeddingModelId,
                embeddingDimension: EmbeddingService.embeddingDimension,
                status: WorldBookEmbeddingStatus.indexed.rawValue,
                embeddedAt: Date(timeIntervalSince1970: 1),
                lastAttemptAt: Date(timeIntervalSince1970: 1),
                lastError: nil,
                updatedAt: Date(timeIntervalSince1970: 1)
            )
        )
    }

    private func makeEmbedding() -> [Float] {
        var embedding = Array(repeating: Float(0), count: EmbeddingService.embeddingDimension)
        embedding[0] = 0.7
        return embedding
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
            try WorldBookEntryEmbeddingMetaRecord
                .filter(Column("entryId") == entryId)
                .fetchCount(db)
        }
    }

    private func entryCount(id: String, in manager: DatabaseManager) async throws -> Int {
        try await manager.read { db in
            try WorldBookEntryRecord
                .filter(Column("id") == id)
                .fetchCount(db)
        }
    }
}
