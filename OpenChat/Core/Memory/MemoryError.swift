import Foundation

enum MemoryType: String, Codable, CaseIterable, Sendable {
    case event
    case fact
    case relationship
    case summary
}

enum MemoryError: LocalizedError, Sendable {
    case modelLoadFailed(underlying: Error)
    case embeddingFailed(underlying: Error)
    case vectorStoreError(underlying: Error)
    case extractionFailed(reason: String)
    case invalidExtractionResponse

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let error):
            "Failed to load embedding model: \(error.localizedDescription)"
        case .embeddingFailed(let error):
            "Failed to generate embedding: \(error.localizedDescription)"
        case .vectorStoreError(let error):
            "Vector store error: \(error.localizedDescription)"
        case .extractionFailed(let reason):
            "Memory extraction failed: \(reason)"
        case .invalidExtractionResponse:
            "Invalid memory extraction response from API"
        }
    }
}
