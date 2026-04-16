import Foundation

enum APIMode: String, Codable, Sendable, CaseIterable {
    case chatCompletions
    case responses
}
