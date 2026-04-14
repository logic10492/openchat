import Foundation

enum PromptError: LocalizedError, @unchecked Sendable {
    case invalidJSON(field: String, underlying: Error)
    case invalidWorldBookPosition(String)
    case emptyResult(String)

    var errorDescription: String? {
        switch self {
        case let .invalidJSON(field, underlying):
            return "Invalid JSON in \(field): \(underlying.localizedDescription)"
        case let .invalidWorldBookPosition(value):
            return "Invalid world book position: \(value)"
        case let .emptyResult(message):
            return message
        }
    }
}
