import Foundation

struct ChatCompletionResponse: Codable, Sendable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable, Sendable {
        let index: Int
        let message: ChatMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct Usage: Codable, Sendable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

struct ChatCompletionChunk: Codable, Sendable {
    let id: String
    let choices: [ChunkChoice]

    struct ChunkChoice: Codable, Sendable {
        let index: Int
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Codable, Sendable {
        let role: String?
        let content: String?
    }
}

struct StreamDelta: Sendable, Equatable {
    let content: String
    let finishReason: String?
}

struct APIErrorEnvelope: Codable, Sendable {
    let error: APIErrorMessage?
}

struct APIErrorMessage: Codable, Sendable {
    let message: String?
}

// MARK: - Models List

struct ModelsListResponse: Codable, Sendable {
    let data: [ModelObject]
}

struct ModelObject: Codable, Sendable, Identifiable {
    let id: String
    let object: String?
    let ownedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, object
        case ownedBy = "owned_by"
    }
}
