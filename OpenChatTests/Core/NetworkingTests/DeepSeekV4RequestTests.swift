import Foundation
import Testing

@testable import OpenChat

@Suite("DeepSeek V4 request encoding")
struct DeepSeekV4RequestTests {
    @Test func test_deepseek_v4_thinking_enabled_uses_thinking_and_reasoning_effort() throws {
        let endpoint = TestHelpers.makeEndpoint(
            baseURL: "https://api.deepseek.com",
            modelName: "deepseek-v4-pro",
            maxContextTokens: 1_000_000,
            providerDialect: .deepSeekV4
        )
        let params = ModelParameters(
            temperature: 0.2,
            topP: 0.5,
            maxTokens: 2048,
            frequencyPenalty: 0.4,
            presencePenalty: 0.7,
            thinkingBudget: 8192,
            reasoningEffort: .max
        )

        let request = APIRequest(messages: [.init(role: "user", content: "Hi")], endpoint: endpoint, parameters: params, stream: false)
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["model"] as? String == "deepseek-v4-pro")
        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "enabled")
        #expect(json["reasoning_effort"] as? String == "max")
        #expect(json["max_tokens"] as? Int == 2048)
        #expect(json["max_completion_tokens"] == nil)
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
        #expect(json["frequency_penalty"] == nil)
        #expect(json["presence_penalty"] == nil)
    }

    @Test func test_deepseek_v4_thinking_disabled_is_explicit() throws {
        let endpoint = TestHelpers.makeEndpoint(
            baseURL: "https://api.deepseek.com",
            modelName: "deepseek-v4-flash",
            maxContextTokens: 1_000_000,
            providerDialect: .deepSeekV4
        )
        let params = ModelParameters(
            temperature: 0.7,
            topP: 0.9,
            maxTokens: 1024,
            thinkingBudget: nil,
            reasoningEffort: .high
        )

        let request = APIRequest(messages: [.init(role: "user", content: "Hi")], endpoint: endpoint, parameters: params, stream: false)
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let thinking = try #require(json["thinking"] as? [String: Any])
        #expect(thinking["type"] as? String == "disabled")
        #expect(json["reasoning_effort"] == nil)
        #expect(json["max_tokens"] as? Int == 1024)
        #expect(json["max_completion_tokens"] == nil)
        #expect(json["temperature"] as? Double == 0.7)
        #expect(json["top_p"] as? Double == 0.9)
    }

    @Test func test_openai_compatible_thinking_keeps_existing_max_completion_tokens_behavior() throws {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "gpt-4o-mini",
            providerDialect: .openAICompatible
        )
        let params = ModelParameters(maxTokens: 2048, thinkingBudget: 4096, reasoningEffort: .max)

        let request = APIRequest(messages: [], endpoint: endpoint, parameters: params, stream: false)
        let data = try JSONEncoder().encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["thinking"] == nil)
        #expect(json["reasoning_effort"] == nil)
        #expect(json["max_completion_tokens"] as? Int == 6144)
        #expect(json["max_tokens"] == nil)
    }
}

@Suite("DeepSeek V4 reasoning content")
struct DeepSeekV4ReasoningContentTests {
    @Test func test_non_streaming_response_decodes_reasoning_content() throws {
        let json = """
        {
          "id": "chatcmpl-deepseek",
          "choices": [
            {
              "index": 0,
              "message": {
                "role": "assistant",
                "reasoning_content": "I should answer from the character's point of view.",
                "content": "I remember the old gate clearly."
              },
              "finish_reason": "stop"
            }
          ],
          "usage": {
            "prompt_tokens": 10,
            "completion_tokens": 20,
            "total_tokens": 30,
            "completion_tokens_details": {
              "reasoning_tokens": 8
            }
          }
        }
        """

        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: Data(json.utf8))

        #expect(response.choices[0].message.reasoningContent == "I should answer from the character's point of view.")
        #expect(response.choices[0].message.content == "I remember the old gate clearly.")
        #expect(response.usage?.completionTokensDetails?.reasoningTokens == 8)
    }

    @Test func test_request_message_omits_reasoning_content_by_default() throws {
        let message = ChatMessage(
            role: "assistant",
            content: "Visible character reply.",
            reasoningContent: "Private role-perspective thinking."
        )

        let data = try JSONEncoder().encode(message.requestMessage())
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["role"] as? String == "assistant")
        #expect(json["content"] as? String == "Visible character reply.")
        #expect(json["reasoning_content"] == nil)
    }
}
