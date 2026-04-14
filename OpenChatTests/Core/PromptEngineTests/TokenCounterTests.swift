import Testing

@testable import OpenChat

@Suite("Token counter")
struct TokenCounterTests {
    @Test func test_ascii_text_counts_reasonably() {
        #expect(TokenCounter.count("abcd") == 1)
        #expect(TokenCounter.count("abcdefgh") == 2)
    }

    @Test func test_cjk_text_counts_reasonably() {
        #expect(TokenCounter.count("你好") == 3)
        #expect(TokenCounter.count(message: .init(role: "user", content: "你好")) == 7)
    }
}
