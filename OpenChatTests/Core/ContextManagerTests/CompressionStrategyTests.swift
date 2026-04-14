import Foundation
import Testing

@testable import OpenChat

@Suite("Compression strategy")
struct CompressionStrategyTests {
    @Test func test_process_returns_summary_and_recent_messages() async throws {
        let conversationId = UUID().uuidString
        let messages = [
            TestHelpers.makeMessage(conversationId: conversationId, role: "user", content: "old one", sortOrder: 1),
            TestHelpers.makeMessage(conversationId: conversationId, role: "assistant", content: "old two", sortOrder: 2),
            TestHelpers.makeMessage(conversationId: conversationId, role: "user", content: "recent", sortOrder: 3),
            TestHelpers.makeMessage(conversationId: conversationId, role: "assistant", content: "latest", sortOrder: 4)
        ]
        let summaryResponse = #"{"id":"abc","choices":[{"index":0,"message":{"role":"assistant","content":"summary"},"finish_reason":"stop"}]}"#
        let session = MockURLProtocol.makeSession { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(summaryResponse.utf8))
        }
        let client = APIClient(session: session)
        let endpoint = TestHelpers.makeEndpoint()

        let result = try await CompressionStrategy(apiClient: client, endpoint: endpoint).process(allMessages: messages, tokenBudget: 10)

        #expect(result.first?.isCompressed == true)
        #expect(result.first?.content.contains("Previously") == true)
        #expect(result.last?.content == "latest")
    }
}
