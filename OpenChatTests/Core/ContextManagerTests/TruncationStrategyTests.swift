import Foundation
import Testing

@testable import OpenChat

@Suite("Truncation strategy")
struct TruncationStrategyTests {
    @Test func test_process_keeps_tail_and_last_pair() async throws {
        let conversationId = UUID().uuidString
        let messages = [
            TestHelpers.makeMessage(conversationId: conversationId, role: "user", content: "one", sortOrder: 1),
            TestHelpers.makeMessage(conversationId: conversationId, role: "assistant", content: "two", sortOrder: 2),
            TestHelpers.makeMessage(conversationId: conversationId, role: "user", content: "three", sortOrder: 3),
            TestHelpers.makeMessage(conversationId: conversationId, role: "assistant", content: "four", sortOrder: 4)
        ]

        let result = try await TruncationStrategy().process(allMessages: messages, tokenBudget: 2)
        #expect(result.count == 2)
        #expect(result.map { $0.content } == ["three", "four"])
    }
}
