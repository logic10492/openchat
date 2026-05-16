import Foundation

struct AgentExecutionContext: Sendable, Equatable {
    let requestId: String
    let now: Date
    let localeIdentifier: String
}
