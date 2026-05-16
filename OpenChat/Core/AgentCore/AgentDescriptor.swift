import Foundation

struct AgentDescriptor: Sendable, Codable, Equatable {
    let id: String
    let kind: AgentKind
    let displayName: String
    let version: String
    let purpose: String
}

enum AgentKind: String, Codable, Sendable, CaseIterable {
    case backgroundWorker = "backgroundWorker"
    case director = "director"
    case librarian = "librarian"
    case reflect = "reflect"
    case relationshipUpdater = "relationshipUpdater"
    case conversationStateTracker = "conversationStateTracker"
}
