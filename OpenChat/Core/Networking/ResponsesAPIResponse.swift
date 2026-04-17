import Foundation

// MARK: - Non-streaming response

struct ResponseObject: Codable, Sendable {
    let id: String
    let status: String
    let output: [ResponseOutputItem]
    let usage: ResponseUsage?

    func toCompletionResponse() -> ChatCompletionResponse {
        let text = output
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined()

        let choice = ChatCompletionResponse.Choice(
            index: 0,
            message: ChatMessage(role: "assistant", content: text),
            finishReason: status == "completed" ? "stop" : nil
        )
        let mappedUsage = usage.map {
            ChatCompletionResponse.Usage(
                promptTokens: $0.inputTokens,
                completionTokens: $0.outputTokens,
                totalTokens: $0.totalTokens
            )
        }
        return ChatCompletionResponse(id: id, choices: [choice], usage: mappedUsage)
    }
}

struct ResponseOutputItem: Codable, Sendable {
    let id: String?
    let type: String
    let role: String?
    let content: [ResponseContentPart]?
}

struct ResponseContentPart: Codable, Sendable {
    let type: String
    let text: String?
}

struct ResponseUsage: Codable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Streaming event payloads

struct ResponseOutputTextDelta: Codable, Sendable {
    let type: String
    let delta: String
}

struct ResponseReasoningDelta: Codable, Sendable {
    let type: String
    let delta: String
}

struct ResponseCompletedEvent: Codable, Sendable {
    let type: String
    let response: ResponseCompletedPayload
}

struct ResponseCompletedPayload: Codable, Sendable {
    let id: String
    let status: String
    let usage: ResponseUsage?
}
