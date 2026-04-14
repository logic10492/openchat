import Foundation

enum APIError: LocalizedError, @unchecked Sendable {
    case invalidURL(String)
    case httpError(statusCode: Int, body: String?)
    case decodingError(underlying: Error)
    case streamParsingError(String)
    case networkError(underlying: Error)
    case cancelled
    case noEndpointConfigured

    var errorDescription: String? {
        switch self {
        case let .invalidURL(value):
            return "Invalid API URL: \(value)"
        case let .httpError(statusCode, body):
            if let body, !body.isEmpty {
                return "HTTP \(statusCode): \(body)"
            }
            return "HTTP \(statusCode)"
        case let .decodingError(underlying):
            return "Failed to decode API response: \(underlying.localizedDescription)"
        case let .streamParsingError(message):
            return "Failed to parse SSE stream: \(message)"
        case let .networkError(underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .cancelled:
            return "Request cancelled"
        case .noEndpointConfigured:
            return "No API endpoint configured"
        }
    }
}
