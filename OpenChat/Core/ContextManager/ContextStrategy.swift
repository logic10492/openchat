import Foundation

enum ContextStrategy: String, Codable, CaseIterable, Sendable {
    case truncation
    case compression
}

protocol ContextStrategyProtocol {
    func process(
        allMessages: [MessageRecord],
        tokenBudget: Int
    ) async throws -> [MessageRecord]
}
