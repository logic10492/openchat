import Foundation
import GRDB
import Testing

@testable import OpenChat

private struct FixedWorldBookEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        var embedding = Array(repeating: Float(0), count: EmbeddingService.embeddingDimension)
        embedding[0] = isQuery ? 1 : 0.8
        embedding[1] = Float(text.count % 97) / 100
        return embedding
    }
}

private struct FailingWorldBookEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        throw MemoryError.modelLoadFailed(
            underlying: NSError(
                domain: "WorldBookEmbeddingIndexerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced embedding failure"]
            )
        )
    }
}

private struct SelectiveFailingWorldBookEmbeddingProvider: EmbeddingProvider {
    let failedNeedle: String

    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        if text.contains(failedNeedle) {
            throw MemoryError.modelLoadFailed(
                underlying: NSError(
                    domain: "WorldBookEmbeddingIndexerTests",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "selective embedding failure"]
                )
            )
        }
        return try FixedWorldBookEmbeddingProvider().embed(text, isQuery: isQuery)
    }
}

@Suite("WorldBookEmbeddingIndexer")
struct WorldBookEmbeddingIndexerTests {
    @Test func test_rebuild_indexes_existing_entries_without_meta() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let indexer = makeIndexer(manager: manager, store: store)
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-a")
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)

        let result = try await indexer.rebuildAllMissingOrStale(limit: nil)

        let meta = try await fetchMeta(entryId: entry.id, in: manager)
        let expectedContentHash = try expectedHash(for: entry)
        #expect(result.indexedCount == 1)
        #expect(result.skippedFreshCount == 0)
        #expect(result.failed.isEmpty)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 1)
        #expect(meta?.statusValue == .indexed)
        #expect(meta?.contentHash == expectedContentHash)
        #expect(meta?.embeddedAt != nil)
        #expect(meta?.lastAttemptAt != nil)
        #expect(meta?.lastError == nil)
    }

    @Test func test_rebuild_skips_fresh_meta() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-a")
        let existingMeta = indexedMeta(entryId: entry.id, contentHash: try expectedHash(for: entry))
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)
        try await store.upsert(
            entryId: entry.id,
            embedding: makeEmbedding(firstValue: 0.4),
            meta: existingMeta
        )
        let indexer = WorldBookEmbeddingIndexer(
            databaseManager: manager,
            embeddingProvider: FailingWorldBookEmbeddingProvider(),
            vectorStore: store
        )

        let result = try await indexer.rebuildAllMissingOrStale(limit: nil)

        let meta = try await fetchMeta(entryId: entry.id, in: manager)
        #expect(result.indexedCount == 0)
        #expect(result.skippedFreshCount == 1)
        #expect(result.failed.isEmpty)
        #expect(meta?.contentHash == existingMeta.contentHash)
        #expect(meta?.lastError == nil)
    }

    @Test func test_rebuild_reindexes_hash_mismatch() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let indexer = makeIndexer(manager: manager, store: store)
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-a")
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)
        try await manager.write { db in
            try indexedMeta(entryId: entry.id, contentHash: "old-hash").insert(db)
        }

        let result = try await indexer.rebuildAllMissingOrStale(limit: nil)

        let meta = try await fetchMeta(entryId: entry.id, in: manager)
        let expectedContentHash = try expectedHash(for: entry)
        #expect(result.indexedCount == 1)
        #expect(result.skippedFreshCount == 0)
        #expect(result.failed.isEmpty)
        #expect(meta?.contentHash == expectedContentHash)
        #expect(meta?.statusValue == .indexed)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 1)
    }

    @Test func test_failed_embedding_records_failed_meta_without_deleting_entry() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let indexer = WorldBookEmbeddingIndexer(
            databaseManager: manager,
            embeddingProvider: FailingWorldBookEmbeddingProvider(),
            vectorStore: store
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-a")
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)

        do {
            _ = try await indexer.index(entry: entry)
            Issue.record("Expected failed embedding to throw")
        } catch let error as WorldBookError {
            guard case .embeddingFailed(let entryId, _) = error else {
                Issue.record("Expected WorldBookError.embeddingFailed, got \(error)")
                return
            }
            #expect(entryId == entry.id)
        } catch {
            Issue.record("Expected WorldBookError.embeddingFailed, got \(error)")
        }

        let meta = try await fetchMeta(entryId: entry.id, in: manager)
        let expectedContentHash = try expectedHash(for: entry)
        #expect(meta?.statusValue == .failed)
        #expect(meta?.contentHash == expectedContentHash)
        #expect(meta?.lastAttemptAt != nil)
        #expect(meta?.lastError?.contains("forced embedding failure") == true)
        #expect(try await entryCount(id: entry.id, in: manager) == 1)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 0)
    }

    @Test func test_invalid_keywords_records_failed_meta_without_embedding() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let indexer = makeIndexer(manager: manager, store: store)
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        var entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "bad-keywords")
        entry.keywords = "{not json]"
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)

        do {
            _ = try await indexer.index(entry: entry)
            Issue.record("Expected invalid keywords to throw")
        } catch let error as WorldBookError {
            guard case .invalidKeywords(let entryId, _) = error else {
                Issue.record("Expected WorldBookError.invalidKeywords, got \(error)")
                return
            }
            #expect(entryId == entry.id)
        } catch {
            Issue.record("Expected WorldBookError.invalidKeywords, got \(error)")
        }

        let meta = try await fetchMeta(entryId: entry.id, in: manager)
        #expect(meta?.statusValue == .failed)
        #expect(meta?.contentHash == "")
        #expect(meta?.lastAttemptAt != nil)
        #expect(meta?.lastError?.contains("Invalid world book keywords") == true)
        #expect(try await entryCount(id: entry.id, in: manager) == 1)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 0)
    }

    @Test func test_batch_rebuild_continues_after_single_entry_failure() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let indexer = WorldBookEmbeddingIndexer(
            databaseManager: manager,
            embeddingProvider: SelectiveFailingWorldBookEmbeddingProvider(failedNeedle: "Broken"),
            vectorStore: store
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-a")
        let good = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "good-entry",
            title: "Silverwood",
            content: "The silver forest is safe."
        )
        let bad = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "bad-entry",
            title: "Broken Gate",
            content: "Broken gate lore."
        )
        try await insertWorldBooks([worldBook], entries: [good, bad], into: manager)

        let result = try await indexer.rebuildAllMissingOrStale(limit: nil)

        let goodMeta = try await fetchMeta(entryId: good.id, in: manager)
        let badMeta = try await fetchMeta(entryId: bad.id, in: manager)
        #expect(result.indexedCount == 1)
        #expect(result.skippedFreshCount == 0)
        #expect(result.failed.map(\.entryId) == [bad.id])
        #expect(goodMeta?.statusValue == .indexed)
        #expect(badMeta?.statusValue == .failed)
        #expect(try await vectorRowCount(entryId: good.id, in: manager) == 1)
        #expect(try await vectorRowCount(entryId: bad.id, in: manager) == 0)
        #expect(try await entryCount(id: good.id, in: manager) == 1)
        #expect(try await entryCount(id: bad.id, in: manager) == 1)
    }

    private func makeIndexer(
        manager: DatabaseManager,
        store: WorldBookVectorStore
    ) -> WorldBookEmbeddingIndexer {
        WorldBookEmbeddingIndexer(
            databaseManager: manager,
            embeddingProvider: FixedWorldBookEmbeddingProvider(),
            vectorStore: store
        )
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

    private func fetchMeta(
        entryId: String,
        in manager: DatabaseManager
    ) async throws -> WorldBookEntryEmbeddingMetaRecord? {
        try await manager.read { db in
            try WorldBookEntryEmbeddingMetaRecord.fetchOne(db, key: entryId)
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

    private func entryCount(id: String, in manager: DatabaseManager) async throws -> Int {
        try await manager.read { db in
            try WorldBookEntryRecord
                .filter(Column("id") == id)
                .fetchCount(db)
        }
    }

    private func expectedHash(for entry: WorldBookEntryRecord) throws -> String {
        try WorldBookEntryHasher.hash(
            embeddingText: WorldBookEmbeddingTextBuilder.text(for: entry),
            modelId: EmbeddingService.embeddingModelId,
            dimension: EmbeddingService.embeddingDimension
        )
    }

    private func indexedMeta(entryId: String, contentHash: String) -> WorldBookEntryEmbeddingMetaRecord {
        let now = Date(timeIntervalSince1970: 1)
        return WorldBookEntryEmbeddingMetaRecord(
            entryId: entryId,
            contentHash: contentHash,
            embeddingModel: EmbeddingService.embeddingModelId,
            embeddingDimension: EmbeddingService.embeddingDimension,
            status: WorldBookEmbeddingStatus.indexed.rawValue,
            embeddedAt: now,
            lastAttemptAt: now,
            lastError: nil,
            updatedAt: now
        )
    }

    private func makeEmbedding(firstValue: Float) -> [Float] {
        var embedding = Array(repeating: Float(0), count: EmbeddingService.embeddingDimension)
        embedding[0] = firstValue
        return embedding
    }
}
