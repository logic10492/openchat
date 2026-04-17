import Foundation

struct ModelParameters: Codable, Equatable, Sendable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int?
    var frequencyPenalty: Double
    var presencePenalty: Double
    var stop: [String]?
    var thinkingBudget: Int?

    init(
        temperature: Double = 0.8,
        topP: Double = 1.0,
        maxTokens: Int? = nil,
        frequencyPenalty: Double = 0.0,
        presencePenalty: Double = 0.0,
        stop: [String]? = nil,
        thinkingBudget: Int? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stop = stop
        self.thinkingBudget = thinkingBudget
    }

    /// Whether thinking/reasoning mode is enabled.
    var isThinkingEnabled: Bool { thinkingBudget != nil }

    func forAPIMode(_ mode: APIMode) -> ModelParameters {
        switch mode {
        case .chatCompletions:
            return self
        case .responses:
            return ModelParameters(
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens,
                frequencyPenalty: 0.0,
                presencePenalty: 0.0,
                stop: nil,
                thinkingBudget: thinkingBudget
            )
        }
    }
}
