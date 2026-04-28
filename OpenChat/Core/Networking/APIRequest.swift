import Foundation

struct APIRequest: Codable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, stop
        case streamOptions = "stream_options"
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
    }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try container.decode(String.self, forKey: .model)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        stream = try container.decode(Bool.self, forKey: .stream)
        streamOptions = try container.decodeIfPresent(StreamOptions.self, forKey: .streamOptions)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        topP = try container.decodeIfPresent(Double.self, forKey: .topP)
        maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
        maxCompletionTokens = try container.decodeIfPresent(Int.self, forKey: .maxCompletionTokens)
        frequencyPenalty = try container.decodeIfPresent(Double.self, forKey: .frequencyPenalty)
        presencePenalty = try container.decodeIfPresent(Double.self, forKey: .presencePenalty)
        stop = try container.decodeIfPresent([String].self, forKey: .stop)
        thinkingEnabled = maxCompletionTokens != nil
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
