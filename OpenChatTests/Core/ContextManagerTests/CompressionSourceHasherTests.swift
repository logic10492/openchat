import Testing

@testable import OpenChat

@Suite("Compression source hasher")
struct CompressionSourceHasherTests {
    @Test func test_hash_is_stable_for_same_messages() {
        let messages = [
            TestHelpers.makeMessage(conversationId: "c", role: "user", content: "hello", sortOrder: 1),
            TestHelpers.makeMessage(conversationId: "c", role: "assistant", content: "world", sortOrder: 2)
        ]

        let first = CompressionSourceHasher.hash(messages: messages)
        let second = CompressionSourceHasher.hash(messages: messages)

        #expect(first == second)
        #expect(first.count == 64)
    }

    @Test func test_hash_changes_when_content_changes() {
        let original = [
            TestHelpers.makeMessage(conversationId: "c", role: "user", content: "hello", sortOrder: 1)
        ]
        let edited = [
            TestHelpers.makeMessage(conversationId: "c", role: "user", content: "hello edited", sortOrder: 1)
        ]

        #expect(CompressionSourceHasher.hash(messages: original) != CompressionSourceHasher.hash(messages: edited))
    }

    @Test func test_hash_can_chain_previous_checkpoint() {
        let messages = [
            TestHelpers.makeMessage(conversationId: "c", role: "user", content: "new", sortOrder: 3)
        ]

        let chained = CompressionSourceHasher.hash(previousSourceHash: "abc", messages: messages)
        let unchained = CompressionSourceHasher.hash(messages: messages)

        #expect(chained != unchained)
    }
}
