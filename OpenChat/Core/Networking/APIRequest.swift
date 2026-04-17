import Foundation

struct APIRequest: Sendable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let streamOptions: StreamOptions?
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let stop: [String]?

    /// When non-nil, the model is expected to produce reasoning tokens.
    let thinkingEnabled: Bool

    init(messages: [ChatMessage], endpoint: APIEndpointConfig, parameters: ModelParameters, stream: Bool) {
        model = endpoint.modelName
        self.messages = messages
        self.stream = stream
        streamOptions = stream ? StreamOptions(includeUsage: true) : nil
        topP = parameters.topP
        frequencyPenalty = parameters.frequencyPenalty
        presencePenalty = parameters.presencePenalty
        stop = parameters.stop
        thinkingEnabled = parameters.isThinkingEnabled

        if parameters.isThinkingEnabled {
            // Reasoning models use max_completion_tokens (includes both reasoning + visible output)
            temperature = 1.0
            maxTokens = nil
            maxCompletionTokens = parameters.maxTokens.map { $0 + (parameters.thinkingBudget ?? 0) }
                ?? parameters.thinkingBudget
        } else {
            temperature = parameters.temperature
            maxTokens = parameters.maxTokens
            maxCompletionTokens = nil
        }
    }
}

extension APIRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, stop
        case streamOptions = "stream_options"
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encode(stream, forKey: .stream)
        try container.encodeIfPresent(streamOptions, forKey: .streamOptions)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(frequencyPenalty, forKey: .frequencyPenalty)
        try container.encodeIfPresent(presencePenalty, forKey: .presencePenalty)
        try container.encodeIfPresent(stop, forKey: .stop)

        // Reasoning models: max_completion_tokens; standard models: max_tokens
        if thinkingEnabled {
            try container.encodeIfPresent(maxCompletionTokens, forKey: .maxCompletionTokens)
        } else {
            try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        }
    }
}

struct StreamOptions: Codable, Sendable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}
