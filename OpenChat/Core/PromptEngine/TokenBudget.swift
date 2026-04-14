import Foundation

struct TokenBudget: Hashable, Sendable {
    let totalBudget: Int
    let fixedTokens: Int
    let exampleDialogsBudget: Int
    let worldBookBudget: Int
    let historyBudget: Int

    static func calculate(
        totalBudget: Int,
        fixedTokens: Int,
        exampleDialogsTokens: Int,
        worldBookTokens: Int
    ) -> TokenBudget {
        let remaining = max(totalBudget - fixedTokens, 0)
        let exampleDialogsBudget = min(Int(Double(remaining) * 0.25), exampleDialogsTokens)
        let worldBookBudget = min(Int(Double(remaining) * 0.35), worldBookTokens)
        let historyBudget = max(remaining - exampleDialogsBudget - worldBookBudget, 0)
        return TokenBudget(
            totalBudget: totalBudget,
            fixedTokens: fixedTokens,
            exampleDialogsBudget: exampleDialogsBudget,
            worldBookBudget: worldBookBudget,
            historyBudget: historyBudget
        )
    }
}
