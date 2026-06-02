import Foundation

struct ResponsesAPIRequest: Codable, Sendable {
    let model: String
    let input: [ChatMessage]
    let instructions: String?
    let stream: Bool
    let temperature: Double?
    let topP: Double?
    let maxOutputTokens: Int?
    let store: Bool
    let reasoning: ReasoningConfig?

    init(messages: [ChatMessage], endpoint: APIEndpointConfig, parameters: ModelParameters, stream: Bool) {
        model = endpoint.modelName
        self.stream = stream
        store = false

        var systemParts: [String] = []
        var nonSystemMessages: [ChatMessage] = []
        for message in messages {
            if message.role == "system" {
                systemParts.append(message.content)
            } else {
                nonSystemMessages.append(message.requestMessage())
            }
        }

        instructions = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n")
        input = nonSystemMessages

        let filtered = parameters.forAPIMode(.responses)
        temperature = filtered.temperature
        topP = filtered.topP
        maxOutputTokens = filtered.maxTokens

        if filtered.isThinkingEnabled {
            reasoning = ReasoningConfig(effort: filtered.reasoningEffort.requestValue(for: endpoint.providerDialect))
        } else {
            reasoning = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case model, input, instructions, stream, temperature, store, reasoning
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
    }
}

struct ReasoningConfig: Codable, Sendable {
    let effort: String
}
