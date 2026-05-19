import Foundation

struct AgentPolicy: Sendable, Codable, Equatable {
    let allowedCapabilities: Set<AgentCapability>
    let tokenBudget: AgentTokenBudget
    let timeoutSeconds: Double
    let retryPolicy: AgentRetryPolicy
    let schemaRepairPolicy: SchemaRepairPolicy
    let visibilityPolicy: AgentVisibilityPolicy
    let toolUsePolicy: ToolUsePolicy
    let sideEffectPolicy: SideEffectPolicy
    let confirmationPolicy: ConfirmationPolicy
}

struct AgentTokenBudget: Sendable, Codable, Equatable {
    let maxInputTokens: Int
    let maxOutputTokens: Int
    let maxTotalTokens: Int
}

struct AgentRetryPolicy: Sendable, Codable, Equatable {
    let maxAttempts: Int
    let retryDelaySeconds: Double
}

struct SchemaRepairPolicy: Sendable, Codable, Equatable {
    let allowRepair: Bool
    let maxRepairAttempts: Int
}

struct AgentVisibilityPolicy: Sendable, Codable, Equatable {
    let exposeDiagnosticsToUser: Bool
    let exposeDraftToUser: Bool
}

struct ConfirmationPolicy: Sendable, Codable, Equatable {
    let requiredForDraftApply: Bool
    let requiredForPersistentWrite: Bool
}

extension AgentPolicy {
    static func backgroundWorkerDefault() -> AgentPolicy {
        AgentPolicy(
            allowedCapabilities: [.deterministic, .internalDiagnostics],
            tokenBudget: AgentTokenBudget(
                maxInputTokens: 8_000,
                maxOutputTokens: 1_000,
                maxTotalTokens: 9_000
            ),
            timeoutSeconds: 5,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1, retryDelaySeconds: 0),
            schemaRepairPolicy: SchemaRepairPolicy(allowRepair: false, maxRepairAttempts: 0),
            visibilityPolicy: AgentVisibilityPolicy(
                exposeDiagnosticsToUser: false,
                exposeDraftToUser: false
            ),
            toolUsePolicy: .disabled,
            sideEffectPolicy: .readOnly,
            confirmationPolicy: ConfirmationPolicy(
                requiredForDraftApply: false,
                requiredForPersistentWrite: true
            )
        )
    }

    static func directorDefault(allowsLLM: Bool = false) -> AgentPolicy {
        var capabilities: Set<AgentCapability> = [.deterministic, .internalDiagnostics]
        if allowsLLM {
            capabilities.insert(.llm)
        }

        return AgentPolicy(
            allowedCapabilities: capabilities,
            tokenBudget: AgentTokenBudget(
                maxInputTokens: 12_000,
                maxOutputTokens: 2_000,
                maxTotalTokens: 14_000
            ),
            timeoutSeconds: 10,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1, retryDelaySeconds: 0),
            schemaRepairPolicy: SchemaRepairPolicy(allowRepair: allowsLLM, maxRepairAttempts: allowsLLM ? 1 : 0),
            visibilityPolicy: AgentVisibilityPolicy(
                exposeDiagnosticsToUser: true,
                exposeDraftToUser: false
            ),
            toolUsePolicy: .disabled,
            sideEffectPolicy: .readOnly,
            confirmationPolicy: ConfirmationPolicy(
                requiredForDraftApply: false,
                requiredForPersistentWrite: true
            )
        )
    }

    static func librarianDraftDefault() -> AgentPolicy {
        AgentPolicy(
            allowedCapabilities: [.llm, .webSearch, .userVisibleDraft, .internalDiagnostics],
            tokenBudget: AgentTokenBudget(
                maxInputTokens: 16_000,
                maxOutputTokens: 4_000,
                maxTotalTokens: 20_000
            ),
            timeoutSeconds: 30,
            retryPolicy: AgentRetryPolicy(maxAttempts: 2, retryDelaySeconds: 1),
            schemaRepairPolicy: SchemaRepairPolicy(allowRepair: true, maxRepairAttempts: 1),
            visibilityPolicy: AgentVisibilityPolicy(
                exposeDiagnosticsToUser: true,
                exposeDraftToUser: true
            ),
            toolUsePolicy: ToolUsePolicy(
                allowedToolNames: ["exa"],
                allowNetwork: true,
                requireCitations: true
            ),
            sideEffectPolicy: .readOnly,
            confirmationPolicy: ConfirmationPolicy(
                requiredForDraftApply: true,
                requiredForPersistentWrite: true
            )
        )
    }

    static func reflectDefault() -> AgentPolicy {
        AgentPolicy(
            allowedCapabilities: [.llm, .databaseRead, .internalDiagnostics],
            tokenBudget: AgentTokenBudget(
                maxInputTokens: 8_000,
                maxOutputTokens: 700,
                maxTotalTokens: 8_700
            ),
            timeoutSeconds: 30,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1, retryDelaySeconds: 0),
            schemaRepairPolicy: SchemaRepairPolicy(allowRepair: false, maxRepairAttempts: 0),
            visibilityPolicy: AgentVisibilityPolicy(
                exposeDiagnosticsToUser: false,
                exposeDraftToUser: false
            ),
            toolUsePolicy: .disabled,
            sideEffectPolicy: SideEffectPolicy(
                allowDatabaseRead: true,
                allowDatabaseWrite: false,
                requiresUserConfirmationForWrite: true
            ),
            confirmationPolicy: ConfirmationPolicy(
                requiredForDraftApply: false,
                requiredForPersistentWrite: true
            )
        )
    }
}
