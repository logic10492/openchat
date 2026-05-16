import Foundation

struct AgentDiagnostics: Sendable, Codable, Equatable {
    let taskName: String
    let agent: AgentDescriptor
    let policy: AgentPolicy
    let startedAt: Date
    let endedAt: Date?
    let inputSummary: [String: String]
    let selectedIds: [String]
    let omittedIds: [String]
    let fallbackReason: String?
    let toolUsage: [AgentToolUsage]
    let tokenUsage: AgentTokenUsage?
    let schemaValidation: SchemaValidationResult?
    let errors: [AgentDiagnosticError]

    static func make(
        taskName: String,
        agent: AgentDescriptor,
        policy: AgentPolicy,
        startedAt: Date,
        endedAt: Date? = nil,
        inputSummary: [String: String] = [:],
        selectedIds: [String] = [],
        omittedIds: [String] = [],
        fallbackReason: String? = nil,
        toolUsage: [AgentToolUsage] = [],
        tokenUsage: AgentTokenUsage? = nil,
        schemaValidation: SchemaValidationResult? = nil,
        errors: [AgentDiagnosticError] = []
    ) -> AgentDiagnostics {
        AgentDiagnostics(
            taskName: taskName,
            agent: agent,
            policy: policy,
            startedAt: startedAt,
            endedAt: endedAt,
            inputSummary: inputSummary,
            selectedIds: selectedIds,
            omittedIds: omittedIds,
            fallbackReason: fallbackReason,
            toolUsage: toolUsage,
            tokenUsage: tokenUsage,
            schemaValidation: schemaValidation,
            errors: errors
        )
    }
}

struct AgentToolUsage: Sendable, Codable, Equatable {
    let toolName: String
    let callCount: Int
    let inputSummary: String?
    let outputSummary: String?
}

struct AgentTokenUsage: Sendable, Codable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
}

struct AgentDiagnosticError: Sendable, Codable, Equatable {
    let code: String
    let message: String
}
