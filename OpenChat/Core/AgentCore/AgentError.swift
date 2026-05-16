import Foundation

enum AgentError: LocalizedError, Sendable, Equatable {
    case capabilityDenied(agentId: String, capability: AgentCapability)
    case networkDenied(agentId: String)
    case databaseWriteDenied(agentId: String)
    case executionFailed(agentId: String, message: String)

    var errorDescription: String? {
        switch self {
        case let .capabilityDenied(agentId, capability):
            return "Agent \(agentId) is not allowed to use capability \(capability.rawValue)."
        case let .networkDenied(agentId):
            return "Agent \(agentId) is not allowed to use network tools."
        case let .databaseWriteDenied(agentId):
            return "Agent \(agentId) is not allowed to write to the database."
        case let .executionFailed(agentId, message):
            return "Agent \(agentId) execution failed: \(message)"
        }
    }
}
