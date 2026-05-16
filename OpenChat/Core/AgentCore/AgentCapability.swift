import Foundation

enum AgentCapability: String, Codable, Sendable, CaseIterable {
    case deterministic = "deterministic"
    case llm = "llm"
    case webSearch = "webSearch"
    case databaseRead = "databaseRead"
    case databaseWrite = "databaseWrite"
    case userVisibleDraft = "userVisibleDraft"
    case internalDiagnostics = "internalDiagnostics"
}
