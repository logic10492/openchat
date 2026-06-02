import Foundation
import Testing

@testable import OpenChat

// MARK: - APIRequest Thinking Tests

@Suite("APIRequest thinking mode")
struct APIRequestThinkingTests {
    @Test func test_decodes_chat_completion_request_payload() throws {
        let json = """
        {
            "model": "gpt-4o-mini",
            "messages": [{"role": "user", "content": "Hi"}],
            "stream": true,
            "stream_options": {"include_usage": true},
            "temperature": 1.0,
            "top_p": 1.0,
            "max_completion_tokens": 6144,
            "frequency_penalty": 0.0,
            "presence_penalty": 0.0
        }
        """

        let request = try JSONDecoder().decode(APIRequest.self, from: Data(json.utf8))

        #expect(request.model == "gpt-4o-mini")
        #expect(request.messages == [ChatMessage(role: "user", content: "Hi")])
        #expect(request.stream == true)
        #expect(request.streamOptions?.includeUsage == true)
        #expect(request.maxTokens == nil)
        #expect(request.maxCompletionTokens == 6144)
        #expect(request.thinkingEnabled == true)
    }

    @Test func test_standard_mode_uses_max_tokens() throws {
        let endpoint = TestHelpers.makeEndpoint()
        let params = ModelParameters(maxTokens: 2048)
        let request = APIRequest(messages: [], endpoint: endpoint, parameters: params, stream: false)

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["max_tokens"] as? Int == 2048)
        #expect(json["max_completion_tokens"] == nil)
    }

    @Test func test_thinking_mode_uses_reasoning_effort_and_completion_cap() throws {
        let endpoint = TestHelpers.makeEndpoint()
        let params = ModelParameters(maxTokens: 2048, thinkingBudget: 4096)
        let request = APIRequest(messages: [], endpoint: endpoint, parameters: params, stream: false)

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["max_tokens"] == nil)
        #expect(json["max_completion_tokens"] as? Int == 2048)
        #expect(json["reasoning_effort"] as? String == "high")
    }

    @Test func test_thinking_mode_sets_temperature_to_1() throws {
        let endpoint = TestHelpers.makeEndpoint()
        let params = ModelParameters(temperature: 0.5, thinkingBudget: 4096)
        let request = APIRequest(messages: [], endpoint: endpoint, parameters: params, stream: false)

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["temperature"] as? Double == 1.0)
    }

    @Test func test_thinking_mode_without_maxTokens_uses_effort_only() throws {
        let endpoint = TestHelpers.makeEndpoint()
        let params = ModelParameters(maxTokens: nil, thinkingBudget: 8192)
        let request = APIRequest(messages: [], endpoint: endpoint, parameters: params, stream: false)

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["max_tokens"] == nil)
        #expect(json["max_completion_tokens"] == nil)
        #expect(json["reasoning_effort"] as? String == "high")
    }

    @Test func test_openai_compatible_maps_legacy_max_effort_to_xhigh() throws {
        let endpoint = TestHelpers.makeEndpoint(modelName: "gpt-5.5")
        let params = ModelParameters(thinkingEnabled: true, reasoningEffort: .max)
        let request = APIRequest(messages: [], endpoint: endpoint, parameters: params, stream: false)

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["reasoning_effort"] as? String == "xhigh")
        #expect(json["max_tokens"] == nil)
        #expect(json["max_completion_tokens"] == nil)
    }
}

// MARK: - Delta Reasoning Content Tests

@Suite("ChatCompletionChunk reasoning")
struct ChunkReasoningTests {
    @Test func test_delta_decodes_reasoning_content() throws {
        let json = """
        {
            "id": "chunk1",
            "choices": [{
                "index": 0,
                "delta": {
                    "reasoning_content": "Let me think about this...",
                    "content": null
                }
            }]
        }
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8))

        #expect(chunk.choices[0].delta.reasoningContent == "Let me think about this...")
        #expect(chunk.choices[0].delta.content == nil)
    }

    @Test func test_delta_without_reasoning_content_defaults_to_nil() throws {
        let json = """
        {
            "id": "chunk1",
            "choices": [{
                "index": 0,
                "delta": {
                    "content": "Hello"
                }
            }]
        }
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: Data(json.utf8))

        #expect(chunk.choices[0].delta.reasoningContent == nil)
        #expect(chunk.choices[0].delta.content == "Hello")
    }
}

// MARK: - Usage Reasoning Tokens Tests

@Suite("Usage reasoning tokens")
struct UsageReasoningTokensTests {
    @Test func test_usage_decodes_reasoning_tokens() throws {
        let json = """
        {
            "prompt_tokens": 100,
            "completion_tokens": 200,
            "total_tokens": 300,
            "completion_tokens_details": {
                "reasoning_tokens": 150
            }
        }
        """
        let usage = try JSONDecoder().decode(ChatCompletionResponse.Usage.self, from: Data(json.utf8))

        #expect(usage.promptTokens == 100)
        #expect(usage.completionTokens == 200)
        #expect(usage.totalTokens == 300)
        #expect(usage.completionTokensDetails?.reasoningTokens == 150)
    }

    @Test func test_usage_without_details_defaults_to_nil() throws {
        let json = """
        {
            "prompt_tokens": 10,
            "completion_tokens": 20,
            "total_tokens": 30
        }
        """
        let usage = try JSONDecoder().decode(ChatCompletionResponse.Usage.self, from: Data(json.utf8))

        #expect(usage.completionTokensDetails == nil)
    }
}

// MARK: - StreamDelta Reasoning Tests

@Suite("StreamDelta reasoning")
struct StreamDeltaReasoningTests {
    @Test func test_stream_delta_with_reasoning() {
        let delta = StreamDelta(content: "", reasoningContent: "thinking...", finishReason: nil)

        #expect(delta.content == "")
        #expect(delta.reasoningContent == "thinking...")
        #expect(delta.finishReason == nil)
    }

    @Test func test_stream_delta_without_reasoning() {
        let delta = StreamDelta(content: "Hello", finishReason: nil)

        #expect(delta.content == "Hello")
        #expect(delta.reasoningContent == nil)
    }

    @Test func test_stream_usage_with_reasoning_tokens() {
        let usage = StreamUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30, reasoningTokens: 15)

        #expect(usage.reasoningTokens == 15)
    }

    @Test func test_stream_usage_defaults_reasoning_to_zero() {
        let usage = StreamUsage(promptTokens: 10, completionTokens: 20, totalTokens: 30)

        #expect(usage.reasoningTokens == 0)
    }
}

// MARK: - Streaming Reasoning Integration

@Suite("Streaming reasoning integration")
struct StreamingReasoningIntegrationTests {
    @Test func test_stream_reasoning_then_content() async throws {
        let payload = """
        data: {"id":"1","choices":[{"index":0,"delta":{"reasoning_content":"Let me think"}}]}

        data: {"id":"1","choices":[{"index":0,"delta":{"reasoning_content":"...done"}}]}

        data: {"id":"1","choices":[{"index":0,"delta":{"content":"The answer is 42"}}]}

        data: {"id":"1","choices":[{"index":0,"delta":{"content":""},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30,"completion_tokens_details":{"reasoning_tokens":8}}}

        data: [DONE]
        """
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(payload.utf8))
        }

        let endpoint = TestHelpers.makeEndpoint()
        let client = APIClient(session: session)

        var deltas: [StreamDelta] = []
        for try await delta in client.streamMessage(
            messages: [.init(role: "user", content: "What is 6*7?")],
            endpoint: endpoint,
            parameters: ModelParameters(thinkingBudget: 4096)
        ) {
            deltas.append(delta)
        }

        // First two deltas should have reasoning content
        #expect(deltas[0].reasoningContent == "Let me think")
        #expect(deltas[0].content == "")
        #expect(deltas[1].reasoningContent == "...done")
        #expect(deltas[1].content == "")

        // Third delta should have visible content
        #expect(deltas[2].content == "The answer is 42")
        #expect(deltas[2].reasoningContent == nil)

        // Last delta should have usage with reasoning tokens
        let lastWithUsage = deltas.first(where: { $0.usage != nil })
        #expect(lastWithUsage?.usage?.reasoningTokens == 8)
    }
}

// MARK: - ModelParameters Thinking Tests

@Suite("ModelParameters thinking")
struct ModelParametersThinkingTests {
    @Test func test_isThinkingEnabled_true_when_budget_set() {
        let params = ModelParameters(thinkingBudget: 4096)
        #expect(params.isThinkingEnabled == true)
    }

    @Test func test_isThinkingEnabled_false_when_nil() {
        let params = ModelParameters()
        #expect(params.isThinkingEnabled == false)
    }

    @Test func test_forAPIMode_responses_preserves_thinking_budget() {
        let params = ModelParameters(thinkingBudget: 8192)
        let filtered = params.forAPIMode(.responses)
        #expect(filtered.thinkingBudget == 8192)
    }

    @Test func test_thinkingBudget_roundtrips_through_codable() throws {
        let original = ModelParameters(maxTokens: 1024, thinkingBudget: 4096)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelParameters.self, from: data)
        #expect(decoded.isThinkingEnabled == true)
        #expect(decoded.thinkingBudget == 4096)
        #expect(decoded.maxTokens == 1024)
    }

    @Test func test_thinking_enabled_roundtrips_without_budget() throws {
        let original = ModelParameters(maxTokens: 1024, thinkingEnabled: true, reasoningEffort: .xhigh)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ModelParameters.self, from: data)
        #expect(decoded.isThinkingEnabled == true)
        #expect(decoded.thinkingBudget == nil)
        #expect(decoded.reasoningEffort == .xhigh)
    }
}

// MARK: - ResponsesAPIRequest Thinking Tests

@Suite("ResponsesAPIRequest thinking")
struct ResponsesAPIRequestThinkingTests {
    @Test func test_reasoning_config_encoded_when_thinking_enabled() throws {
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let params = ModelParameters(thinkingEnabled: true, reasoningEffort: .xhigh)
        let request = ResponsesAPIRequest(messages: [.init(role: "user", content: "Hi")], endpoint: endpoint, parameters: params, stream: false)

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let reasoning = json["reasoning"] as? [String: Any]
        #expect(reasoning != nil)
        #expect(reasoning?["effort"] as? String == "xhigh")
        #expect(reasoning?["max_tokens"] == nil)
    }

    @Test func test_no_reasoning_config_when_budget_nil() throws {
        let endpoint = TestHelpers.makeEndpoint(apiMode: .responses)
        let params = ModelParameters()
        let request = ResponsesAPIRequest(messages: [.init(role: "user", content: "Hi")], endpoint: endpoint, parameters: params, stream: false)

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json["reasoning"] == nil)
    }
}

// MARK: - Database Reasoning Content Tests

@Suite("MessageRecord reasoning")
struct MessageRecordReasoningTests {
    @Test func test_message_record_stores_reasoning_content() async throws {
        let db = try TestHelpers.makeDatabaseManager()

        let conversation = TestHelpers.makeConversation()
        try await db.saveConversation(conversation)

        var message = TestHelpers.makeMessage(
            conversationId: conversation.id,
            role: "assistant",
            content: "The answer is 42",
            sortOrder: 1
        )
        message.reasoningContent = "Let me calculate 6 times 7..."
        try await db.saveMessage(message)

        let fetched = try await db.fetchMessages(conversationId: conversation.id)
        #expect(fetched.count == 1)
        #expect(fetched[0].reasoningContent == "Let me calculate 6 times 7...")
        #expect(fetched[0].content == "The answer is 42")
    }

    @Test func test_message_record_reasoning_nil_by_default() async throws {
        let db = try TestHelpers.makeDatabaseManager()

        let conversation = TestHelpers.makeConversation()
        try await db.saveConversation(conversation)

        let message = TestHelpers.makeMessage(
            conversationId: conversation.id,
            role: "assistant",
            content: "Hello",
            sortOrder: 1
        )
        try await db.saveMessage(message)

        let fetched = try await db.fetchMessages(conversationId: conversation.id)
        #expect(fetched[0].reasoningContent == nil)
    }
}

// MARK: - StreamingStats Reasoning Tests

@Suite("StreamingStats reasoning tokens")
struct StreamingStatsReasoningTests {
    @Test func test_stats_with_reasoning_tokens() {
        let stats = StreamingStats(
            inputTokens: 100,
            outputTokens: 50,
            reasoningTokens: 30,
            tokensPerSecond: 10.0,
            contextRemainingPercent: 0.5,
            totalBudget: 4096
        )
        #expect(stats.reasoningTokens == 30)
    }

    @Test func test_stats_defaults_reasoning_to_zero() {
        let stats = StreamingStats(
            inputTokens: 100,
            outputTokens: 50,
            tokensPerSecond: 10.0,
            contextRemainingPercent: 0.5,
            totalBudget: 4096
        )
        #expect(stats.reasoningTokens == 0)
    }
}
