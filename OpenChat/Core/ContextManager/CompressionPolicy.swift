import Foundation

struct CompressionPolicy: Equatable, Sendable {
    static let standardContextRatio = 0.4
    static let highIntelligenceContextRatio = 0.25
    static let highIntelligenceCompactRatio = 0.9

    let endpoint: APIEndpointConfig
    let compressionMode: CompressionMode

    init(endpoint: APIEndpointConfig, compressionMode: CompressionMode = .standard) {
        self.endpoint = endpoint
        self.compressionMode = compressionMode
    }

    var promptTokenBudget: Int {
        max(Int((Double(endpoint.maxContextTokens) * Self.standardContextRatio).rounded(.down)), 1)
    }

    var effectiveCompactWindowTokens: Int {
        switch compressionMode {
        case .standard:
            return max(endpoint.maxContextTokens, 1)
        case .highIntelligence:
            return max(Int((Double(endpoint.maxContextTokens) * Self.highIntelligenceContextRatio).rounded(.down)), 1)
        }
    }

    var codexStyleCompactLimit: Int {
        max(Int((Double(effectiveCompactWindowTokens) * Self.highIntelligenceCompactRatio).rounded(.down)), 1)
    }

    var autoCompactTokenLimit: Int {
        switch compressionMode {
        case .standard:
            return promptTokenBudget
        case .highIntelligence:
            return codexStyleCompactLimit
        }
    }

    func historyBudget(fixedTokens: Int) -> Int {
        max(autoCompactTokenLimit - fixedTokens, 0)
    }
}
