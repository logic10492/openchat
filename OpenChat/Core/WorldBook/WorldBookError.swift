import Foundation

enum WorldBookError: LocalizedError, Sendable {
    case invalidKeywords(entryId: String, underlying: Error)
    case embeddingFailed(entryId: String, underlying: Error)
    case indexerError(underlying: Error)
    case vectorStoreError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidKeywords(let entryId, let error):
            "Invalid world book keywords for entry \(entryId): \(error.localizedDescription)"
        case .embeddingFailed(let entryId, let error):
            "World book embedding failed for entry \(entryId): \(error.localizedDescription)"
        case .indexerError(let error):
            "World book indexer error: \(error.localizedDescription)"
        case .vectorStoreError(let error):
            "World book vector store error: \(error.localizedDescription)"
        }
    }
}
