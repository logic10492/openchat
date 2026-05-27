import Testing
import Foundation

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

    @Test func test_messageDisplayItem_appendReasoningDelta_updatesReasoningRevisionOnly() {
        let record = MessageRecord(
            id: "assistant-reasoning",
            conversationId: "conversation-1",
            role: "assistant",
            content: "",
            tokenCount: nil,
            isCompressed: false,
            originalContent: nil,
            sortOrder: 1,
            createdAt: .now,
            reasoningContent: nil
        )
        var item = MessageDisplayItem(record: record)
        let originalContentRevision = item.contentRenderRevision
        let originalStreamingRevision = item.streamingRenderRevision

        item.appendReasoningContentDelta("Thinking")

        #expect(item.content.isEmpty)
        #expect(item.reasoningContent == "Thinking")
        #expect(item.contentRenderRevision == originalContentRevision)
        #expect(item.streamingRenderRevision != originalStreamingRevision)
    }

    @Test func test_markdownLayout_joinsNewlineBlocksIntoSingleRenderSurface() {
        let blocks = TextContentBlock.makeBlocks(from: "动作一\n台词一")
        let layout = MarkdownTextLayoutPlan(blocks: blocks)

        #expect(blocks.map(\.text) == ["动作一\n", "台词一"])
        #expect(layout.plainText == "动作一\n台词一")
        #expect(layout.renderSurfaceCount == 1)
    }

    @Test func test_messageDisplayItem_compactsExcessBlankLinesOnlyForRendering() {
        let record = MessageRecord(
            id: "assistant-blank-lines",
            conversationId: "conversation-1",
            role: "assistant",
            content: "动作一\n\n\n\n台词一",
            tokenCount: nil,
            isCompressed: false,
            originalContent: nil,
            sortOrder: 1,
            createdAt: .now,
            reasoningContent: nil
        )
        var item = MessageDisplayItem(record: record)

        #expect(item.content == "动作一\n\n\n\n台词一")
        #expect(item.contentBlocks.map(\.text).joined() == "动作一\n\n台词一")

        item.appendContentDelta("\n\n\n动作二")

        #expect(item.content == "动作一\n\n\n\n台词一\n\n\n动作二")
        #expect(item.contentBlocks.map(\.text).joined() == "动作一\n\n台词一\n\n动作二")
    }

    @Test func test_markdownRefreshDelay_getsLazierForLongerText() {
        #expect(MarkdownRenderPolicy.refreshDelay(forCharacterCount: 100) == .milliseconds(30))
        #expect(MarkdownRenderPolicy.refreshDelay(forCharacterCount: 800) == .milliseconds(50))
        #expect(MarkdownRenderPolicy.refreshDelay(forCharacterCount: 2_000) == .milliseconds(75))
        #expect(MarkdownRenderPolicy.refreshDelay(forCharacterCount: 5_000) == .milliseconds(100))
    }

    @Test func test_streamingRenderBuffer_coalescesSmallDeltasUntilInterval() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var buffer = StreamingRenderBuffer(
            minimumFlushInterval: 0.05,
            maximumBufferedCharacters: 20,
            now: start
        )

        buffer.append(content: "a")
        #expect(buffer.flushIfNeeded(now: start.addingTimeInterval(0.02)) == nil)

        let timedBatch = buffer.flushIfNeeded(now: start.addingTimeInterval(0.06))
        #expect(timedBatch?.content == "a")
        #expect(timedBatch?.reasoningContent == "")

        buffer.append(content: "01234567890123456789", reasoningContent: "r")
        let sizeBatch = buffer.flushIfNeeded(now: start.addingTimeInterval(0.07))
        #expect(sizeBatch?.content == "01234567890123456789")
        #expect(sizeBatch?.reasoningContent == "r")
    }
}
