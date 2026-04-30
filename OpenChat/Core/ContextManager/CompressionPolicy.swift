import Foundation

struct CompressionPolicy: Equatable, Sendable {
    static let codexGPT55EffectiveWindowTokens = 258_000
    static let codexAutoCompactRatio = 0.9

    let endpoint: APIEndpointConfig

    var promptTokenBudget: Int {
        max(Int((Double(endpoint.maxContextTokens) * AppConstants.contextRatio).rounded(.down)), 1)
    }

    var effectiveCompactWindowTokens: Int {
        if Self.isGPT55Family(endpoint.modelName) {
            return min(endpoint.maxContextTokens, Self.codexGPT55EffectiveWindowTokens)
        }
        return endpoint.maxContextTokens
    }

    var codexStyleCompactLimit: Int {
        max(Int((Double(effectiveCompactWindowTokens) * Self.codexAutoCompactRatio).rounded(.down)), 1)
    }

    var autoCompactTokenLimit: Int {
        min(promptTokenBudget, codexStyleCompactLimit)
    }

    func historyBudget(fixedTokens: Int) -> Int {
        max(autoCompactTokenLimit - fixedTokens, 0)
    }

    private static func isGPT55Family(_ modelName: String) -> Bool {
        let normalized = modelName.lowercased()
        return normalized == "gpt-5.5"
            || normalized.hasPrefix("gpt-5.5-")
            || normalized.hasPrefix("gpt5.5")
            || normalized.hasPrefix("gpt-5_5")
    }
}
