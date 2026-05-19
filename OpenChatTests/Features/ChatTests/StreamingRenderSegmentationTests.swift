import Testing

@testable import OpenChat

@Suite("Streaming render segmentation")
struct StreamingRenderSegmentationTests {
    @Test func test_textContentBlockAppender_splitsNewlineAcrossChunks() {
        var blocks = TextContentBlock.makeBlocks(from: "First")

        blocks = TextContentBlock.appending(" line\nSecond", to: blocks)

        #expect(blocks.map(\.text) == ["First line\n", "Second"])
        #expect(blocks.map(\.id) == [0, 1])
    }

    @Test func test_textContentBlockAppender_splitsLongUnbrokenText() {
        let longText = String(repeating: "a", count: 1_201)

        let blocks = TextContentBlock.makeBlocks(from: longText)

        #expect(blocks.count == 2)
        #expect(blocks[0].text.count == 1_200)
        #expect(blocks[1].text.count == 1)
    }

    @Test func test_messageDisplayItem_appendDelta_updatesBlocksAndRevision() {
        let record = MessageRecord(
            id: "assistant-1",
            conversationId: "conversation-1",
            role: "assistant",
            content: "Hello",
            tokenCount: nil,
            isCompressed: false,
            originalContent: nil,
            sortOrder: 1,
            createdAt: .now,
            reasoningContent: nil
        )
        var item = MessageDisplayItem(record: record)
        let originalRevision = item.contentRenderRevision

        item.appendContentDelta(", world\nNext line")

        #expect(item.content == "Hello, world\nNext line")
        #expect(item.contentBlocks.map(\.text) == ["Hello, world\n", "Next line"])
        #expect(item.contentRenderRevision != originalRevision)
    }

    @Test func test_markdownRefreshDelay_getsLazierForLongerText() {
        #expect(MarkdownRenderPolicy.refreshDelay(forCharacterCount: 100) == .milliseconds(30))
        #expect(MarkdownRenderPolicy.refreshDelay(forCharacterCount: 800) == .milliseconds(50))
        #expect(MarkdownRenderPolicy.refreshDelay(forCharacterCount: 2_000) == .milliseconds(75))
        #expect(MarkdownRenderPolicy.refreshDelay(forCharacterCount: 5_000) == .milliseconds(100))
    }
}
