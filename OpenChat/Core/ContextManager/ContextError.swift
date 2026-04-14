import Foundation

enum ContextError: LocalizedError, Sendable {
    case historyLoadFailed(String)
    case compressionFailed(String)
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case let .historyLoadFailed(message):
            return "Failed to load context history: \(message)"
        case let .compressionFailed(message):
            return "Failed to compress context: \(message)"
        case .invalidEndpoint:
            return "Missing compression endpoint"
        }
    }
}
