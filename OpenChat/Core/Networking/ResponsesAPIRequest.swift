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
                nonSystemMessages.append(message)
            }
        }

        instructions = systemParts.isEmpty ? nil : systemParts.joined(separator: "\n")
        input = nonSystemMessages

        let filtered = parameters.forAPIMode(.responses)
        temperature = filtered.temperature
        topP = filtered.topP
        maxOutputTokens = filtered.maxTokens
    }

    enum CodingKeys: String, CodingKey {
        case model, input, instructions, stream, temperature, store
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
    }
}
