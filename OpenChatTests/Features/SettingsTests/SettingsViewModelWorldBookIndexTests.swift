import Foundation
import GRDB
import Testing

@testable import OpenChat

private struct FixedSettingsEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        var embedding = Array(repeating: Float(0), count: EmbeddingService.embeddingDimension)
        embedding[0] = isQuery ? 1 : 0.6
        embedding[1] = Float(text.count % 83) / 100
        return embedding
    }
}

@MainActor
@Suite("Settings world book semantic index")
struct SettingsViewModelWorldBookIndexTests {
    @Test func test_rebuild_world_book_semantic_index_backfills_existing_entries() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook(id: "world-settings")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-settings")
        try await manager.saveWorldBook(worldBook)
        try await manager.saveWorldBookEntry(entry)
        let viewModel = SettingsViewModel(
            databaseManager: manager,
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore(),
            worldBookEmbeddingIndexer: makeIndexer(manager: manager),
            appState: AppState()
        )

        await viewModel.rebuildWorldBookSemanticIndex()

        #expect(viewModel.isRebuildingWorldBookIndex == false)
        #expect(viewModel.worldBookIndexStatusMessage?.isEmpty == false)
        #expect(viewModel.worldBookIndexStatusMessage?.contains("skipped") == false)
        #expect(viewModel.worldBookIndexStatusMessage?.contains("跳过") == false)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 1)
        #expect(try await fetchMeta(entryId: entry.id, in: manager)?.statusValue == .indexed)
    }

    @Test func test_rebuild_world_book_semantic_index_preserves_content_records() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let worldBook = TestHelpers.makeWorldBook(id: "world-settings-preserve")
        var character = TestHelpers.makeCharacterCard(id: "character-settings-preserve")
        character.worldBookId = worldBook.id
        let entry = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "entry-settings-preserve"
        )
        try await manager.saveWorldBook(worldBook)
        try await manager.saveCharacterCard(character)
        try await manager.saveWorldBookEntry(entry)
        let viewModel = SettingsViewModel(
            databaseManager: manager,
            apiClient: APIClient(),
            apiKeyStore: InMemoryAPIKeyStore(),
            worldBookEmbeddingIndexer: makeIndexer(manager: manager),
            appState: AppState()
        )

        await viewModel.rebuildWorldBookSemanticIndex()

        #expect(try await manager.fetchCharacterCard(id: character.id)?.id == character.id)
        #expect(try await manager.fetchWorldBook(id: worldBook.id)?.id == worldBook.id)
        #expect(try await manager.fetchWorldBookEntries(worldBookId: worldBook.id).map(\.id) == [entry.id])
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 1)
    }

    private func makeIndexer(manager: DatabaseManager) -> WorldBookEmbeddingIndexer {
        let store = WorldBookVectorStore(databaseManager: manager)
        return WorldBookEmbeddingIndexer(
            databaseManager: manager,
            embeddingProvider: FixedSettingsEmbeddingProvider(),
            vectorStore: store
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
}
