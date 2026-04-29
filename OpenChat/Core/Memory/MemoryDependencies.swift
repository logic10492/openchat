import Foundation

protocol EmbeddingProvider: Sendable {
    func embed(_ text: String, isQuery: Bool) throws -> [Float]
}

protocol MemoryVectorStore: Sendable {
    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws
    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws
    func search(
        query: [Float],
        characterCardId: String,
        limit: Int
    ) async throws -> [(entryId: String, distance: Float)]
    func delete(entryId: String) async throws
    func deleteAll(characterCardId: String) async throws
}

extension MemoryVectorStore {
    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws {
        for item in entries {
            try await insert(entry: item.entry, embedding: item.embedding)
        }
    }
}

extension EmbeddingService: EmbeddingProvider {}
extension VectorStore: MemoryVectorStore {}
