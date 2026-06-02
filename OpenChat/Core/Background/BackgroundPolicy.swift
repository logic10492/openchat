import Foundation

struct BackgroundPolicy: Sendable, Equatable {
    let tokenBudget: Int
    let maxEntries: Int
    let perSourceLimits: [BackgroundSourceType: Int]
    let sourceWeights: [BackgroundSourceType: Double]
    let duplicationPenalty: Double
    let lowConfidenceThreshold: Double

    init(
        tokenBudget: Int,
        maxEntries: Int,
        perSourceLimits: [BackgroundSourceType: Int],
        sourceWeights: [BackgroundSourceType: Double],
        duplicationPenalty: Double,
        lowConfidenceThreshold: Double
    ) {
        self.tokenBudget = max(tokenBudget, 0)
        self.maxEntries = max(maxEntries, 0)
        self.perSourceLimits = perSourceLimits.mapValues { max($0, 0) }
        self.sourceWeights = sourceWeights
        self.duplicationPenalty = max(duplicationPenalty, 0)
        self.lowConfidenceThreshold = max(lowConfidenceThreshold, 0)
    }

    static func compatibilityDefault(tokenBudget: Int = 1_024) -> BackgroundPolicy {
        BackgroundPolicy(
            tokenBudget: tokenBudget,
            maxEntries: 20,
            perSourceLimits: [
                .characterState: 1,
                .conversationState: 1,
                .skillReference: 3,
                .worldBook: 10,
                .memory: 10,
            ],
            sourceWeights: [
                .characterState: 0.12,
                .conversationState: 0.08,
                .skillReference: 0.1,
                .worldBook: 0.05,
                .memory: 0.1,
            ],
            duplicationPenalty: 1,
            lowConfidenceThreshold: 0.05
        )
    }

    func limit(for sourceType: BackgroundSourceType) -> Int {
        perSourceLimits[sourceType] ?? maxEntries
    }

    func weight(for sourceType: BackgroundSourceType) -> Double {
        sourceWeights[sourceType] ?? 0
    }

    var profile: [String: String] {
        [
            "tokenBudget": String(tokenBudget),
            "maxEntries": String(maxEntries),
            "memoryLimit": String(limit(for: .memory)),
            "worldBookLimit": String(limit(for: .worldBook)),
            "characterStateLimit": String(limit(for: .characterState)),
            "conversationStateLimit": String(limit(for: .conversationState)),
            "skillReferenceLimit": String(limit(for: .skillReference)),
            "memoryWeight": String(weight(for: .memory)),
            "worldBookWeight": String(weight(for: .worldBook)),
            "characterStateWeight": String(weight(for: .characterState)),
            "conversationStateWeight": String(weight(for: .conversationState)),
            "skillReferenceWeight": String(weight(for: .skillReference)),
            "duplicationPenalty": String(duplicationPenalty),
            "lowConfidenceThreshold": String(lowConfidenceThreshold),
        ]
    }
}
