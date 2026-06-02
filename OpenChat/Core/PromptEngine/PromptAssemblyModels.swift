import Foundation

struct PromptAssemblyPreview: Sendable {
    let stableIdentityMessages: [ChatMessage]
    let currentTurnContextMessages: [ChatMessage]
    let currentTurnMessage: ChatMessage
    let fixedTokens: Int
    let historyBudget: Int
    let tokenUsage: TokenUsageReport
    let triggeredEntries: [String]
}

struct AssemblyResult: Sendable {
    let messages: [ChatMessage]
    let tokenUsage: TokenUsageReport
    let triggeredEntries: [String]
}

struct RoleSkillPromptMaterial: Sendable, Equatable {
    let name: String
    let source: String
    let skillMarkdown: String
}

struct TokenUsageReport: Sendable {
    let totalBudget: Int
    let systemPrompt: Int
    let characterDescription: Int
    let roleSkill: Int
    let scenario: Int
    let slowPlotDirective: Int
    let timeContext: Int
    let background: Int
    let worldBookEntries: Int
    let memories: Int
    let exampleDialogs: Int
    let history: Int
    let currentInput: Int
    let totalUsed: Int
    let remaining: Int
}
