import Foundation

struct TokenBudget: Hashable, Sendable {
    let totalBudget: Int
    let fixedTokens: Int
    let exampleDialogsBudget: Int
    let worldBookBudget: Int
    let memoryBudget: Int
    let historyBudget: Int

    static func calculate(
        totalBudget: Int,
        fixedTokens: Int,
        exampleDialogsTokens: Int,
        worldBookTokens: Int,
        memoryTokens: Int = 0
    ) -> TokenBudget {
        let remaining = max(totalBudget - fixedTokens, 0)
        let exampleDialogsBudget = min(Int(Double(remaining) * 0.25), exampleDialogsTokens)
        let worldBookBudget = min(Int(Double(remaining) * 0.35), worldBookTokens)
        let memoryBudget = min(Int(Double(remaining) * 0.15), memoryTokens)
        let historyBudget = max(remaining - exampleDialogsBudget - worldBookBudget - memoryBudget, 0)
        return TokenBudget(
            totalBudget: totalBudget,
            fixedTokens: fixedTokens,
            exampleDialogsBudget: exampleDialogsBudget,
            worldBookBudget: worldBookBudget,
            memoryBudget: memoryBudget,
            historyBudget: historyBudget
        )
    }
}
