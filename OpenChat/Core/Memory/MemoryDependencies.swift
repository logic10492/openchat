import Foundation

protocol EmbeddingProvider: Sendable {
    func embed(_ text: String, isQuery: Bool) throws -> [Float]
}

protocol MemoryVectorStore: Sendable {
    func insert(entry: MemoryEntryRecord, embedding: [Float]) async throws
    func insert(entry: MemoryEntryRecord, embedding: [Float], links: [MemoryEntryLinkRecord]) async throws
    func insert(entries: [(entry: MemoryEntryRecord, embedding: [Float])]) async throws
    func insert(
        entries: [(entry: MemoryEntryRecord, embedding: [Float])],
        provenances: [String: MemoryEntryProvenanceRecord]
    ) async throws
    func search(
        query: [Float],
        characterCardId: String,
        limit: Int
    ) async throws -> [(entryId: String, distance: Float)]
    func delete(entryId: String) async throws
    func deleteAll(characterCardId: String) async throws
}

extension MemoryVectorStore {
    func insert(entry: MemoryEntryRecord, embedding: [Float], links: [MemoryEntryLinkRecord]) async throws {
        guard links.isEmpty else {
            throw MemoryError.vectorStoreError(
                underlying: MemoryVectorStoreCapabilityError.linksNotSupported
            )
        }
        try await insert(entry: entry, embedding: embedding)
    }

    func insert(
        entries: [(entry: MemoryEntryRecord, embedding: [Float])],
        provenances: [String: MemoryEntryProvenanceRecord]
    ) async throws {
        try await insert(entries: entries)
    }
}

extension EmbeddingService: EmbeddingProvider {}
extension VectorStore: MemoryVectorStore {}

private enum MemoryVectorStoreCapabilityError: LocalizedError, Sendable {
    case linksNotSupported

    var errorDescription: String? {
        "Memory vector store does not support atomic link writes."
    }
}
