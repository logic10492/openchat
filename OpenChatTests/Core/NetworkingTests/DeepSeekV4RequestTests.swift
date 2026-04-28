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
