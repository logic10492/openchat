import Foundation

struct ModelParameters: Codable, Equatable, Sendable {
    static let openChatDefaultTemperature = 0.8
    static let openChatDefaultTopP = 0.95

    var temperature: Double
    var topP: Double
    var maxTokens: Int?
    var frequencyPenalty: Double
    var presencePenalty: Double
    var stop: [String]?
    var thinkingBudget: Int?
    var reasoningEffort: ReasoningEffort

    init(
        temperature: Double = Self.openChatDefaultTemperature,
        topP: Double = 1.0,
        maxTokens: Int? = nil,
        frequencyPenalty: Double = 0.0,
        presencePenalty: Double = 0.0,
        stop: [String]? = nil,
        thinkingBudget: Int? = nil,
        reasoningEffort: ReasoningEffort = .high
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stop = stop
        self.thinkingBudget = thinkingBudget
        self.reasoningEffort = reasoningEffort
    }

    enum CodingKeys: String, CodingKey {
        case temperature, topP, maxTokens, frequencyPenalty, presencePenalty, stop, thinkingBudget, reasoningEffort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        temperature = try container.decode(Double.self, forKey: .temperature)
        topP = try container.decode(Double.self, forKey: .topP)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        frequencyPenalty = try container.decode(Double.self, forKey: .frequencyPenalty)
        presencePenalty = try container.decode(Double.self, forKey: .presencePenalty)
        stop = try container.decodeIfPresent([String].self, forKey: .stop)
        thinkingBudget = try container.decodeIfPresent(Int.self, forKey: .thinkingBudget)
        reasoningEffort = try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .high
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
                thinkingBudget: thinkingBudget,
                reasoningEffort: reasoningEffort
            )
        }
    }
}
