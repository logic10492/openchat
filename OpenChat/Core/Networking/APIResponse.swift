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
        let completionTokensDetails: CompletionTokensDetails?

        init(promptTokens: Int, completionTokens: Int, totalTokens: Int, completionTokensDetails: CompletionTokensDetails? = nil) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
            self.completionTokensDetails = completionTokensDetails
        }

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case completionTokensDetails = "completion_tokens_details"
        }
    }

    struct CompletionTokensDetails: Codable, Sendable {
        let reasoningTokens: Int?

        enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }
}

struct ChatCompletionChunk: Codable, Sendable {
    let id: String
    let choices: [ChunkChoice]
    let usage: ChatCompletionResponse.Usage?

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
        let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case role, content
            case reasoningContent = "reasoning_content"
        }
    }
}

struct StreamDelta: Sendable, Equatable {
    let content: String
    let reasoningContent: String?
    let finishReason: String?
    let usage: StreamUsage?

    init(content: String, finishReason: String?, usage: StreamUsage? = nil) {
        self.content = content
        self.reasoningContent = nil
        self.finishReason = finishReason
        self.usage = usage
    }

    init(content: String, reasoningContent: String?, finishReason: String?, usage: StreamUsage? = nil) {
        self.content = content
        self.reasoningContent = reasoningContent
        self.finishReason = finishReason
        self.usage = usage
    }
}

struct StreamUsage: Sendable, Equatable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let reasoningTokens: Int

    init(promptTokens: Int, completionTokens: Int, totalTokens: Int, reasoningTokens: Int = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.reasoningTokens = reasoningTokens
    }
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

struct ModelObject: Sendable, Identifiable {
    let id: String
    let object: String?
    let ownedBy: String?
    let contextLength: Int?
}

extension ModelObject: Codable {
    enum CodingKeys: String, CodingKey {
        case id, object
        case ownedBy = "owned_by"
        case contextLength = "context_length"
        case maxModelLen = "max_model_len"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        ownedBy = try container.decodeIfPresent(String.self, forKey: .ownedBy)
        // Prefer context_length, fall back to max_model_len (vLLM)
        contextLength = try container.decodeIfPresent(Int.self, forKey: .contextLength)
            ?? container.decodeIfPresent(Int.self, forKey: .maxModelLen)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(object, forKey: .object)
        try container.encodeIfPresent(ownedBy, forKey: .ownedBy)
        try container.encodeIfPresent(contextLength, forKey: .contextLength)
    }
}
