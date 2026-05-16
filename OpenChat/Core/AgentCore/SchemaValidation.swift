import Foundation

struct SchemaValidationResult: Sendable, Codable, Equatable {
    let isValid: Bool
    let repaired: Bool
    let errors: [String]
}
