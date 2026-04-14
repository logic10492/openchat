import Foundation

struct PromptAssemblyPreview: Sendable {
    let messagesBeforeHistory: [ChatMessage]
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

struct TokenUsageReport: Sendable {
    let totalBudget: Int
    let systemPrompt: Int
    let characterDescription: Int
    let scenario: Int
    let worldBookEntries: Int
    let exampleDialogs: Int
    let history: Int
    let currentInput: Int
    let totalUsed: Int
    let remaining: Int
}
