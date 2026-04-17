import Foundation
import Testing

@testable import OpenChat

@Suite("TitleGenerator")
struct TitleGeneratorTests {
    // MARK: - Prompt Construction

    @Test func test_buildPrompt_with_scenario_and_character() {
        let card = TestHelpers.makeCharacterCard(name: "Ava", scenario: "A quiet tavern in the rain.")
        let generator = TitleGenerator(apiClient: APIClient())

        let messages = generator.buildPrompt(
            scenario: "A dark forest at midnight",
            characterCard: card,
            userMessage: "Hello there"
        )

        #expect(messages.count == 2)
        #expect(messages[0].role == "system")
        #expect(messages[0].content == AppConstants.titleGenerationPrompt)
        #expect(messages[1].role == "user")
        #expect(messages[1].content.contains("Character: Ava"))
        #expect(messages[1].content.contains("Scenario: A dark forest at midnight"))
        #expect(messages[1].content.contains("First message: Hello there"))
    }

    @Test func test_buildPrompt_with_scenario_only() {
        let generator = TitleGenerator(apiClient: APIClient())

        let messages = generator.buildPrompt(
            scenario: "A castle siege",
            characterCard: nil,
            userMessage: "We need to breach the walls"
        )

        #expect(messages.count == 2)
        #expect(messages[1].content.contains("Scenario: A castle siege"))
        #expect(messages[1].content.contains("First message: We need to breach the walls"))
        #expect(!messages[1].content.contains("Character:"))
    }

    @Test func test_buildPrompt_with_character_only() {
        let card = TestHelpers.makeCharacterCard(name: "Ava", scenario: nil)
        let generator = TitleGenerator(apiClient: APIClient())

        let messages = generator.buildPrompt(
            scenario: nil,
            characterCard: card,
            userMessage: "Hi"
        )

        #expect(messages.count == 2)
        #expect(messages[1].content.contains("Character: Ava"))
        #expect(!messages[1].content.contains("Scenario:"))
        #expect(messages[1].content.contains("First message: Hi"))
    }

    @Test func test_buildPrompt_with_no_context() {
        let generator = TitleGenerator(apiClient: APIClient())

        let messages = generator.buildPrompt(
            scenario: nil,
            characterCard: nil,
            userMessage: "Just chatting"
        )

        #expect(messages.count == 2)
        #expect(messages[1].content == "First message: Just chatting")
    }

    @Test func test_buildPrompt_trims_whitespace() {
        let card = TestHelpers.makeCharacterCard(name: "  Ava  ", scenario: "  ")
        let generator = TitleGenerator(apiClient: APIClient())

        let messages = generator.buildPrompt(
            scenario: "   ",
            characterCard: card,
            userMessage: "Hello"
        )

        // Empty scenario after trim should not appear
        #expect(messages[1].content.contains("Character: Ava"))
        #expect(!messages[1].content.contains("Scenario:"))
    }

    // MARK: - API Integration

    @Test func test_generateTitle_returns_cleaned_title() async throws {
        let responseBody = #"{"id":"abc","choices":[{"index":0,"message":{"role":"assistant","content":"\"Rainy Tavern Meeting\""},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)
        let generator = TitleGenerator(apiClient: client)
        let endpoint = TestHelpers.makeEndpoint()

        let title = try await generator.generateTitle(
            scenario: "A quiet tavern",
            characterCard: nil,
            userMessage: "Hello",
            endpoint: endpoint,
            parameters: ModelParameters()
        )

        // Surrounding quotes should be removed
        #expect(title == "Rainy Tavern Meeting")
    }

    @Test func test_generateTitle_truncates_long_title() async throws {
        let longTitle = String(repeating: "A", count: 50)
        let responseBody = #"{"id":"abc","choices":[{"index":0,"message":{"role":"assistant","content":"\#(longTitle)"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":50,"total_tokens":60}}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)
        let generator = TitleGenerator(apiClient: client)
        let endpoint = TestHelpers.makeEndpoint()

        let title = try await generator.generateTitle(
            scenario: nil,
            characterCard: nil,
            userMessage: "Hi",
            endpoint: endpoint,
            parameters: ModelParameters()
        )

        // Should be truncated to 30 chars + ellipsis
        #expect(title.count == 31) // 30 + "…"
        #expect(title.hasSuffix("…"))
    }

    @Test func test_generateTitle_throws_on_empty_response() async throws {
        let responseBody = #"{"id":"abc","choices":[{"index":0,"message":{"role":"assistant","content":""},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":0,"total_tokens":10}}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)
        let generator = TitleGenerator(apiClient: client)
        let endpoint = TestHelpers.makeEndpoint()

        await #expect(throws: TitleGenerationError.self) {
            _ = try await generator.generateTitle(
                scenario: nil,
                characterCard: nil,
                userMessage: "Hi",
                endpoint: endpoint,
                parameters: ModelParameters()
            )
        }
    }

    @Test func test_generateTitle_uses_limited_max_tokens() async throws {
        let responseBody = #"{"id":"abc","choices":[{"index":0,"message":{"role":"assistant","content":"A Title"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":3,"total_tokens":13}}"#
        let session = MockURLProtocol.makeSession { request in
            // Verify request is POST to chat completions
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "http://localhost:8080/v1/chat/completions")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)
        let generator = TitleGenerator(apiClient: client)
        let endpoint = TestHelpers.makeEndpoint()

        let title = try await generator.generateTitle(
            scenario: "Test",
            characterCard: nil,
            userMessage: "Hello",
            endpoint: endpoint,
            parameters: ModelParameters(maxTokens: 2048)
        )

        // The title generator should produce a valid title regardless of the conversation's maxTokens
        #expect(title == "A Title")
    }

    @Test func test_generateTitle_removes_curly_quotes() async throws {
        let responseBody = #"{"id":"abc","choices":[{"index":0,"message":{"role":"assistant","content":"\u201CForest Walk\u201D"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":3,"total_tokens":13}}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseBody.utf8))
        }
        let client = APIClient(session: session)
        let generator = TitleGenerator(apiClient: client)
        let endpoint = TestHelpers.makeEndpoint()

        let title = try await generator.generateTitle(
            scenario: nil,
            characterCard: nil,
            userMessage: "Hi",
            endpoint: endpoint,
            parameters: ModelParameters()
        )

        #expect(title == "Forest Walk")
    }
}
