import Foundation
import GRDB
import Testing

@testable import OpenChat

private struct SourceFixedEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        var embedding = Array(repeating: Float(0), count: EmbeddingService.embeddingDimension)
        embedding[0] = 1
        return embedding
    }
}

private struct SourceFailingEmbeddingProvider: EmbeddingProvider {
    func embed(_ text: String, isQuery: Bool) throws -> [Float] {
        throw MemoryError.modelLoadFailed(
            underlying: NSError(
                domain: "WorldBookSourceTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced semantic failure"]
            )
        )
    }
}

@Suite("WorldBookSource")
struct WorldBookSourceTests {
    @Test func test_keyword_only_candidate_is_selected() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let source = WorldBookSource(
            embeddingProvider: SourceFixedEmbeddingProvider(),
            vectorStore: store
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-keyword")
        let entry = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "keyword-entry",
            title: "Dragon Gate",
            keywords: ["dragon"],
            content: "The dragon gate opens at dawn."
        )
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)

        let result = try await source.recallEntries(
            worldBook: worldBook,
            entries: [entry],
            recentMessages: [],
            currentInput: "Tell me about the dragon.",
            limit: 5
        )

        #expect(result.entries.map(\.entry.id) == [entry.id])
        #expect(result.entries.first?.reasons == [.keyword])
        #expect(result.entries.first?.keywordHits == ["dragon"])
        #expect(result.trace.keywordCandidateCount == 1)
    }

    @Test func test_semantic_only_candidate_is_selected_without_keyword_hit() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let source = WorldBookSource(
            embeddingProvider: SourceFixedEmbeddingProvider(),
            vectorStore: store
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-semantic")
        let semanticEntry = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "semantic-entry",
            title: "Moon Archive",
            keywords: ["selenite-vault"],
            content: "The moon archive stores silent maps."
        )
        try await insertWorldBooks([worldBook], entries: [semanticEntry], into: manager)
        try await store.upsert(entryId: semanticEntry.id, embedding: makeEmbedding(firstValue: 1))

        let result = try await source.recallEntries(
            worldBook: worldBook,
            entries: [semanticEntry],
            recentMessages: [],
            currentInput: "Where are the old maps kept?",
            limit: 5
        )

        let recalled = try #require(result.entries.first)
        #expect(recalled.entry.id == semanticEntry.id)
        #expect(recalled.reasons == [.semantic])
        #expect(recalled.keywordRank == nil)
        #expect(recalled.semanticRank == 1)
        #expect(result.trace.semanticCandidateCount == 1)
    }

    @Test func test_keyword_and_semantic_duplicate_merges_reasons() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let source = WorldBookSource(
            embeddingProvider: SourceFixedEmbeddingProvider(),
            vectorStore: store
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-duplicate")
        let entry = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "duplicate-entry",
            title: "Silverwood",
            keywords: ["silverwood"],
            content: "Silverwood paths rearrange under moonlight."
        )
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)
        try await store.upsert(entryId: entry.id, embedding: makeEmbedding(firstValue: 1))

        let result = try await source.recallEntries(
            worldBook: worldBook,
            entries: [entry],
            recentMessages: [],
            currentInput: "Take me to Silverwood.",
            limit: 5
        )

        let recalled = try #require(result.entries.first)
        #expect(result.entries.count == 1)
        #expect(recalled.reasons == [.keyword, .semantic])
        #expect(recalled.keywordRank == 1)
        #expect(recalled.semanticRank == 1)
        #expect(result.trace.omissions.contains { $0.reason == .duplicate && $0.entryId == entry.id })
    }

    @Test func test_disabled_world_book_returns_empty() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let source = WorldBookSource(
            embeddingProvider: SourceFixedEmbeddingProvider(),
            vectorStore: store
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-disabled", isEnabled: false)
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-disabled-world")
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)

        let result = try await source.recallEntries(
            worldBook: worldBook,
            entries: [entry],
            recentMessages: [],
            currentInput: "dragon",
            limit: 5
        )

        #expect(result.entries.isEmpty)
        #expect(result.trace.omissions.contains { $0.reason == .disabled && $0.entryId == entry.id })
    }

    @Test func test_disabled_entry_is_omitted() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let source = WorldBookSource(
            embeddingProvider: SourceFixedEmbeddingProvider(),
            vectorStore: store
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-disabled-entry")
        var disabled = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "disabled-entry",
            keywords: ["dragon"]
        )
        disabled.isEnabled = false
        try await insertWorldBooks([worldBook], entries: [disabled], into: manager)
        try await store.upsert(entryId: disabled.id, embedding: makeEmbedding(firstValue: 1))

        let result = try await source.recallEntries(
            worldBook: worldBook,
            entries: [disabled],
            recentMessages: [],
            currentInput: "dragon",
            limit: 5
        )

        #expect(result.entries.isEmpty)
        #expect(result.trace.omissions.contains { $0.reason == .disabled && $0.entryId == disabled.id })
    }

    @Test func test_semantic_failure_falls_back_to_keyword_only() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = WorldBookVectorStore(databaseManager: manager)
        let source = WorldBookSource(
            embeddingProvider: SourceFailingEmbeddingProvider(),
            vectorStore: store
        )
        let worldBook = TestHelpers.makeWorldBook(id: "world-fallback")
        let entry = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "fallback-entry",
            keywords: ["dragon"],
            content: "Dragon treaties are stored in the west hall."
        )
        try await insertWorldBooks([worldBook], entries: [entry], into: manager)

        let result = try await source.recallEntries(
            worldBook: worldBook,
            entries: [entry],
            recentMessages: [],
            currentInput: "dragon treaty",
            limit: 5
        )

        #expect(result.entries.map(\.entry.id) == [entry.id])
        #expect(result.entries.first?.reasons == [.keyword])
        #expect(result.trace.omissions.contains { $0.reason == .semanticUnavailable })
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

    private func makeEmbedding(firstValue: Float) -> [Float] {
        var embedding = Array(repeating: Float(0), count: EmbeddingService.embeddingDimension)
        embedding[0] = firstValue
        return embedding
    }
}
