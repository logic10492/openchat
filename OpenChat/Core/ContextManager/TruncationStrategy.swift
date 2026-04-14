import Foundation

struct TruncationStrategy: ContextStrategyProtocol {
    func process(
        allMessages: [MessageRecord],
        tokenBudget: Int
    ) async throws -> [MessageRecord] {
        let requiredTail = Array(allMessages.suffix(2))
        guard tokenBudget > 0 else { return requiredTail }

        var result: [MessageRecord] = []
        var remaining = tokenBudget

        for message in allMessages.reversed() {
            let tokens = TokenCounter.count(message: message)
            if remaining - tokens < 0 {
                if result.isEmpty {
                    result.insert(message, at: 0)
                }
                break
            }
            result.insert(message, at: 0)
            remaining -= tokens
        }

        if result.count < requiredTail.count {
            return requiredTail
        }

        return result
    }
}
