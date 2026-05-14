import Foundation
import GRDB
import Testing

@testable import OpenChat

@Suite("VectorStore")
struct VectorStoreTests {
    @Test func test_insert_saves_memory_and_vector_for_character_search() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = VectorStore(databaseManager: manager)
        let card = TestHelpers.makeCharacterCard(id: "card-a")
        try await insertCards([card], into: manager)

        let entry = TestHelpers.makeMemoryEntry(
            id: "memory-a",
            characterCardId: card.id,
            content: "Ava found the hidden map."
        )

        try await store.insert(entry: entry, embedding: makeEmbedding(firstValue: 0.8))

        let memoryCount = try await manager.fetchMemoryCount(characterCardId: card.id)
        let vectorCount = try await vectorRowCount(entryId: entry.id, in: manager)
        let results = try await store.search(
            query: makeEmbedding(firstValue: 1.0),
            characterCardId: card.id,
            limit: 1
        )

        #expect(memoryCount == 1)
        #expect(vectorCount == 1)
        #expect(results.map(\.entryId) == [entry.id])
    }

    @Test func test_search_limits_knn_to_requested_character_before_topK() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = VectorStore(databaseManager: manager)
        let cardA = TestHelpers.makeCharacterCard(id: "card-a")
        let cardB = TestHelpers.makeCharacterCard(id: "card-b")
        try await insertCards([cardA, cardB], into: manager)

        let cardAFirst = TestHelpers.makeMemoryEntry(id: "a-1", characterCardId: cardA.id)
        let cardASecond = TestHelpers.makeMemoryEntry(id: "a-2", characterCardId: cardA.id)
        let cardBFirst = TestHelpers.makeMemoryEntry(id: "b-1", characterCardId: cardB.id)
        let cardBSecond = TestHelpers.makeMemoryEntry(id: "b-2", characterCardId: cardB.id)
        try await manager.saveMemory(cardAFirst)
        try await manager.saveMemory(cardASecond)
        try await manager.saveMemory(cardBFirst)
        try await manager.saveMemory(cardBSecond)

        try await store.insert(entryId: cardAFirst.id, embedding: makeEmbedding(firstValue: 0.8))
        try await store.insert(entryId: cardASecond.id, embedding: makeEmbedding(firstValue: 0.7))
        try await store.insert(entryId: cardBFirst.id, embedding: makeEmbedding(firstValue: 1.0))
        try await store.insert(entryId: cardBSecond.id, embedding: makeEmbedding(firstValue: 0.99))

        let results = try await store.search(
            query: makeEmbedding(firstValue: 1.0),
            characterCardId: cardA.id,
            limit: 2
        )

        #expect(results.map(\.entryId) == [cardAFirst.id, cardASecond.id])
        #expect(results.allSatisfy { $0.distance.isFinite })
        #expect(results[0].distance <= results[1].distance)
    }

    @Test func test_delete_removes_memory_and_vector_rows() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = VectorStore(databaseManager: manager)
        let card = TestHelpers.makeCharacterCard(id: "card-a")
        try await insertCards([card], into: manager)
        let entry = TestHelpers.makeMemoryEntry(id: "memory-a", characterCardId: card.id)
        try await store.insert(entry: entry, embedding: makeEmbedding(firstValue: 0.8))

        #expect(try await manager.fetchMemoryCount(characterCardId: card.id) == 1)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 1)

        try await store.delete(entryId: entry.id)

        let memoryCount = try await manager.fetchMemoryCount(characterCardId: card.id)
        let vectorCount = try await vectorRowCount(entryId: entry.id, in: manager)
        #expect(memoryCount == 0)
        #expect(vectorCount == 0)
    }

    @Test func test_erase_all_data_removes_memory_and_vector_rows() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = VectorStore(databaseManager: manager)
        let card = TestHelpers.makeCharacterCard(id: "card-a")
        try await insertCards([card], into: manager)
        let entry = TestHelpers.makeMemoryEntry(id: "memory-a", characterCardId: card.id)
        try await store.insert(entry: entry, embedding: makeEmbedding(firstValue: 0.8))

        try await manager.eraseAllData(preserveEndpoints: false)

        #expect(try await manager.fetchMemoryCount(characterCardId: card.id) == 0)
        #expect(try await vectorRowCount(entryId: entry.id, in: manager) == 0)
    }

    @Test func test_insert_invalid_dimension_throws_before_partial_write() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = VectorStore(databaseManager: manager)
        let card = TestHelpers.makeCharacterCard(id: "card-a")
        try await insertCards([card], into: manager)
        let entry = TestHelpers.makeMemoryEntry(id: "memory-a", characterCardId: card.id)

        do {
            try await store.insert(entry: entry, embedding: [1, 2, 3])
            Issue.record("Expected invalid vector dimension to throw")
        } catch let error as MemoryError {
            guard case .vectorStoreError = error else {
                Issue.record("Expected MemoryError.vectorStoreError, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected MemoryError.vectorStoreError, got \(error)")
        }

        let memoryCount = try await manager.fetchMemoryCount(characterCardId: card.id)
        let vectorCount = try await vectorRowCount(entryId: entry.id, in: manager)
        #expect(memoryCount == 0)
        #expect(vectorCount == 0)
    }

    @Test func test_insert_rolls_back_memory_when_vector_insert_fails() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = VectorStore(databaseManager: manager)
        let card = TestHelpers.makeCharacterCard(id: "card-a")
        try await insertCards([card], into: manager)
        let entry = TestHelpers.makeMemoryEntry(id: "memory-a", characterCardId: card.id)

        try await store.insert(entryId: entry.id, embedding: makeEmbedding(firstValue: 0.5))

        do {
            try await store.insert(entry: entry, embedding: makeEmbedding(firstValue: 0.8))
            Issue.record("Expected duplicate vector insert to throw")
        } catch let error as MemoryError {
            guard case .vectorStoreError = error else {
                Issue.record("Expected MemoryError.vectorStoreError, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected MemoryError.vectorStoreError, got \(error)")
        }

        let memoryCount = try await manager.fetchMemoryCount(characterCardId: card.id)
        let vectorCount = try await vectorRowCount(entryId: entry.id, in: manager)
        #expect(memoryCount == 0)
        #expect(vectorCount == 1)
    }

    @Test func test_insert_batch_rolls_back_all_memories_when_later_vector_insert_fails() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let store = VectorStore(databaseManager: manager)
        let card = TestHelpers.makeCharacterCard(id: "card-a")
        try await insertCards([card], into: manager)
        let first = TestHelpers.makeMemoryEntry(id: "memory-a", characterCardId: card.id)
        let second = TestHelpers.makeMemoryEntry(id: "memory-b", characterCardId: card.id)

        try await store.insert(entryId: second.id, embedding: makeEmbedding(firstValue: 0.5))

        do {
            try await store.insert(entries: [
                (entry: first, embedding: makeEmbedding(firstValue: 0.8)),
                (entry: second, embedding: makeEmbedding(firstValue: 0.9))
            ])
            Issue.record("Expected duplicate vector insert to throw during batch insert")
        } catch let error as MemoryError {
            guard case .vectorStoreError = error else {
                Issue.record("Expected MemoryError.vectorStoreError, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected MemoryError.vectorStoreError, got \(error)")
        }

        let memoryCount = try await manager.fetchMemoryCount(characterCardId: card.id)
        let firstVectorCount = try await vectorRowCount(entryId: first.id, in: manager)
        let secondVectorCount = try await vectorRowCount(entryId: second.id, in: manager)
        #expect(memoryCount == 0)
        #expect(firstVectorCount == 0)
        #expect(secondVectorCount == 1)
    }

    private func insertCards(_ cards: [CharacterCardRecord], into manager: DatabaseManager) async throws {
        try await manager.write { db in
            for card in cards {
                try card.insert(db)
            }
        }
    }

    private func vectorRowCount(entryId: String, in manager: DatabaseManager) async throws -> Int {
        try await manager.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM memory_embedding WHERE entry_id = ?",
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
