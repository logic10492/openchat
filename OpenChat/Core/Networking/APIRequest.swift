import Foundation

struct APIRequest: Codable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let stop: [String]?

    init(messages: [ChatMessage], endpoint: APIEndpointConfig, parameters: ModelParameters, stream: Bool) {
        model = endpoint.modelName
        self.messages = messages
        self.stream = stream
        temperature = parameters.temperature
        topP = parameters.topP
        maxTokens = parameters.maxTokens
        frequencyPenalty = parameters.frequencyPenalty
        presencePenalty = parameters.presencePenalty
        stop = parameters.stop
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature, stop
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
    }
}
