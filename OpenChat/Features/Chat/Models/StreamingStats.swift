import Foundation

struct StreamingStats: Sendable, Equatable {
    let inputTokens: Int
    let outputTokens: Int
    let reasoningTokens: Int
    let tokensPerSecond: Double
    let contextRemainingPercent: Double
    let totalBudget: Int

    init(
        inputTokens: Int,
        outputTokens: Int,
        reasoningTokens: Int = 0,
        tokensPerSecond: Double,
        contextRemainingPercent: Double,
        totalBudget: Int
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.tokensPerSecond = tokensPerSecond
        self.contextRemainingPercent = contextRemainingPercent
        self.totalBudget = totalBudget
    }

    var contextRemainingFormatted: String {
        String(format: "%.0f%%", contextRemainingPercent * 100)
    }

    var isContextLow: Bool {
        contextRemainingPercent < 0.2
    }
}
