import Foundation
import GRDB
import Testing

@testable import OpenChat

private struct FixedEditorEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        var embedding = Array(repeating: Float(0), count: EmbeddingService.embeddingDimension)
        embedding[0] = isQuery ? 1 : 0.8
        embedding[1] = Float(text.count % 89) / 100
        return embedding
    }
}

private struct FailingEditorEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        throw MemoryError.modelLoadFailed(
            underlying: NSError(
                domain: "WorldBookEditorViewModelTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced editor embedding failure"]
            )
        )
    }
}

@MainActor
@Suite("WorldBookEditorViewModel")
struct WorldBookEditorViewModelTests {
    @Test func test_save_entry_indexes_or_marks_rebuild() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook(id: "world-save")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-save")
        try await manager.saveWorldBook(worldBook)
        let viewModel = makeViewModel(
            manager: manager,
            worldBook: worldBook,
            provider: FixedEditorEmbeddingProvider()
        )

        try await viewModel.saveEntry(entry)

        let meta = try await fetchMeta(entryId: entry.id, in: manager)
        #expect(viewModel.indexingWarningMessage == nil)
        #expect(viewModel.entries.map(\.id) == [entry.id])
        #expect(meta?.statusValue == .indexed)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 1)
    }

    @Test func test_save_entry_keeps_record_when_indexing_fails() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook(id: "world-fail")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-fail")
        try await manager.saveWorldBook(worldBook)
        let viewModel = makeViewModel(
            manager: manager,
            worldBook: worldBook,
            provider: FailingEditorEmbeddingProvider()
        )

        try await viewModel.saveEntry(entry)

        let meta = try await fetchMeta(entryId: entry.id, in: manager)
        #expect(viewModel.indexingWarningMessage?.contains("forced editor embedding failure") == true)
        #expect(try await entryCount(id: entry.id, in: manager) == 1)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 0)
        #expect(meta?.statusValue == .failed)
    }

    @Test func test_save_entry_for_new_world_book_persists_parent_and_rebinds_entry() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let viewModel = makeViewModel(
            manager: manager,
            worldBook: nil,
            provider: FixedEditorEmbeddingProvider()
        )
        viewModel.name = "New Lore"
        let draftEntry = TestHelpers.makeWorldBookEntry(
            worldBookId: "draft-world-book-id",
            id: "entry-new-world",
            title: "First Lore",
            keywords: ["lore"],
            content: "First lore content."
        )

        try await viewModel.saveEntry(draftEntry)

        let savedWorldBooks = try await manager.fetchWorldBooks()
        let savedWorldBook = try #require(savedWorldBooks.first)
        let savedEntries = try await manager.fetchWorldBookEntries(worldBookId: savedWorldBook.id)
        let savedEntry = try #require(savedEntries.first)
        #expect(savedWorldBooks.count == 1)
        #expect(savedWorldBook.name == "New Lore")
        #expect(viewModel.currentWorldBookId == savedWorldBook.id)
        #expect(savedEntry.id == draftEntry.id)
        #expect(savedEntry.worldBookId == savedWorldBook.id)
        #expect(viewModel.entries.map(\.id) == [draftEntry.id])
        #expect(try await vectorRowCount(entryId: draftEntry.id, in: manager) == 1)
        #expect(try await fetchMeta(entryId: draftEntry.id, in: manager)?.statusValue == .indexed)
    }

    @Test func test_import_entries_batches_save_and_index() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let viewModel = makeViewModel(
            manager: manager,
            worldBook: nil,
            provider: FixedEditorEmbeddingProvider()
        )
        viewModel.name = "Imported Lore"
        let parsedEntries = [
            WorldBookImportFormat.ParsedEntry(
                title: "Moon Gate",
                keywords: ["moon", "gate"],
                content: "The moon gate opens at low tide.",
                priority: 80,
                position: WorldBookEntryPosition.beforeHistory.rawValue,
                warnings: []
            ),
            WorldBookImportFormat.ParsedEntry(
                title: "Sun Archive",
                keywords: ["sun"],
                content: "The archive burns cold.",
                priority: 40,
                position: WorldBookEntryPosition.afterSystem.rawValue,
                warnings: []
            ),
        ]

        let result = try await viewModel.importEntries(parsedEntries)

        let savedWorldBooks = try await manager.fetchWorldBooks()
        let savedEntries = try await manager.fetchWorldBookEntries(worldBookId: savedWorldBooks.first?.id)
        #expect(result.importedCount == 2)
        #expect(result.indexedCount == 2)
        #expect(result.failedIndexingCount == 0)
        #expect(savedWorldBooks.map(\.name) == ["Imported Lore"])
        #expect(savedEntries.count == 2)
        #expect(viewModel.entries.count == 2)
        for entry in savedEntries {
            #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 1)
            #expect(try await fetchMeta(entryId: entry.id, in: manager)?.statusValue == .indexed)
        }
    }

    @Test func test_import_entries_reuses_saved_new_world_book_on_later_save() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let viewModel = makeViewModel(
            manager: manager,
            worldBook: nil,
            provider: FixedEditorEmbeddingProvider()
        )
        viewModel.name = "Imported Lore"
        let parsedEntries = [
            WorldBookImportFormat.ParsedEntry(
                title: "Moon Gate",
                keywords: ["moon"],
                content: "The moon gate opens at low tide.",
                priority: 80,
                position: WorldBookEntryPosition.beforeHistory.rawValue,
                warnings: []
            ),
        ]

        _ = try await viewModel.importEntries(parsedEntries)
        viewModel.description = "Updated after import."
        let savedAgain = try await viewModel.save()

        let savedWorldBooks = try await manager.fetchWorldBooks()
        #expect(savedWorldBooks.count == 1)
        #expect(savedWorldBooks.first?.id == savedAgain.id)
        #expect(savedWorldBooks.first?.description == "Updated after import.")
    }

    private func makeViewModel(
        manager: DatabaseManager,
        worldBook: WorldBookRecord?,
        provider: any EmbeddingProvider
    ) -> WorldBookEditorViewModel {
        let store = WorldBookVectorStore(databaseManager: manager)
        let indexer = WorldBookEmbeddingIndexer(
            databaseManager: manager,
            embeddingProvider: provider,
            vectorStore: store
        )
        return WorldBookEditorViewModel(
            databaseManager: manager,
            worldBookEmbeddingIndexer: indexer,
            editingWorldBook: worldBook
        )
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
}
