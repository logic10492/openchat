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

enum MemoryReflectError: LocalizedError, Equatable, Sendable {
    case emptyModelOutput
    case invalidJSON(String)
    case expectedSingleJSONObject
    case multipleObservationsNotSupported
    case missingContent
    case missingBasedOn
    case invalidBasedOn
    case unknownBasedOnIds([String])
    case missingMemoryType
    case invalidMemoryType(String)
    case missingSuggestedAction
    case invalidSuggestedAction(String)
    case invalidConfidence
    case missingSourceMemories([String])
    case crossCharacterMemory(id: String, expectedCharacterCardId: String, actualCharacterCardId: String)
    case emptyAPIResponse
    case promptEncodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyModelOutput:
            "Memory reflect output is empty."
        case .invalidJSON(let reason):
            "Memory reflect output is not valid JSON: \(reason)"
        case .expectedSingleJSONObject:
            "Memory reflect output must be a single JSON object."
        case .multipleObservationsNotSupported:
            "Memory reflect output must not contain multiple observations."
        case .missingContent:
            "Memory reflect output must include non-empty content."
        case .missingBasedOn:
            "Memory reflect output must include non-empty basedOn memory ids."
        case .invalidBasedOn:
            "Memory reflect basedOn must be an array of memory ids."
        case .unknownBasedOnIds(let ids):
            "Memory reflect output referenced unknown source memory ids: \(ids.joined(separator: ", "))."
        case .missingMemoryType:
            "Memory reflect output must include a memory type."
        case .invalidMemoryType(let value):
            "Memory reflect output used an unsupported memory type: \(value)."
        case .missingSuggestedAction:
            "Memory reflect output must include a suggested action."
        case .invalidSuggestedAction(let value):
            "Memory reflect output used an unsupported suggested action: \(value)."
        case .invalidConfidence:
            "Memory reflect confidence must be a number."
        case .missingSourceMemories(let ids):
            "Memory reflect source memories were not found: \(ids.joined(separator: ", "))."
        case let .crossCharacterMemory(id, expected, actual):
            "Memory reflect source memory \(id) belongs to character \(actual), expected \(expected)."
        case .emptyAPIResponse:
            "Memory reflect API response did not include assistant content."
        case .promptEncodingFailed(let reason):
            "Memory reflect prompt encoding failed: \(reason)"
        }
    }
}

enum MemoryReflectApplyError: LocalizedError, Equatable, Sendable {
    case unsupportedAction(MemoryReflectAction)

    var errorDescription: String? {
        switch self {
        case .unsupportedAction(let action):
            "Memory reflect apply only supports insert_observation, got \(action.rawValue)."
        }
    }
}

enum MemoryReflectReviewError: LocalizedError, Equatable, Sendable {
    case invalidSelectionCount(Int)
    case noDefaultEndpoint
    case noDefaultModel(endpointId: String)
    case missingAPIKey(endpointId: String)
    case noDraft

    var errorDescription: String? {
        switch self {
        case .invalidSelectionCount(let count):
            "Select 2 to 5 memories before organizing. Current selection: \(count)."
        case .noDefaultEndpoint:
            "No default API endpoint configured."
        case .noDefaultModel(let endpointId):
            "Default endpoint has no default model: \(endpointId)."
        case .missingAPIKey(let endpointId):
            "Default endpoint is missing an API key: \(endpointId)."
        case .noDraft:
            "No reflect draft is available to apply."
        }
    }
}
