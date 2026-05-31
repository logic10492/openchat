import Foundation

struct StreamingRenderBatch: Equatable {
    let content: String
    let reasoningContent: String

    var isEmpty: Bool {
        content.isEmpty && reasoningContent.isEmpty
    }
}

struct StreamingRenderSnapshot: Sendable {
    let messageID: String
    let content: String
    let contentBlocks: [TextContentBlock]
    let contentRenderRevision: Int
    let reasoningContent: String?
    let reasoningRenderRevision: Int
    let renderedMarkdown: AttributedString?
}

struct StreamingFinalSnapshot: Sendable, Equatable {
    let content: String
    let reasoningContent: String?
    let usage: StreamUsage?
}

actor StreamingResponseAccumulator {
    private let messageID: String
    private let minimumFlushInterval: TimeInterval
    private let maximumBufferedCharacters: Int
    private var lastFlushDate: Date
    private var content: String
    private var reasoningContent: String?
    private var pendingContent = ""
    private var pendingReasoningContent = ""
    private var contentRenderRevision: Int
    private var reasoningRenderRevision: Int
    private var lastUsage: StreamUsage?

    init(
        messageID: String,
        initialContent: String = "",
        initialReasoningContent: String? = nil,
        initialContentRenderRevision: Int,
        initialReasoningRenderRevision: Int,
        minimumFlushInterval: TimeInterval = 0.05,
        maximumBufferedCharacters: Int = 520,
        now: Date = .now
    ) {
        self.messageID = messageID
        self.content = initialContent
        self.reasoningContent = initialReasoningContent
        self.contentRenderRevision = initialContentRenderRevision
        self.reasoningRenderRevision = initialReasoningRenderRevision
        self.minimumFlushInterval = minimumFlushInterval
        self.maximumBufferedCharacters = maximumBufferedCharacters
        self.lastFlushDate = now
    }

    func append(_ delta: StreamDelta, now: Date = .now) -> StreamingRenderSnapshot? {
        if !delta.content.isEmpty {
            content += delta.content
            pendingContent += delta.content
            contentRenderRevision &+= 1
        }
        if let deltaReasoning = delta.reasoningContent, !deltaReasoning.isEmpty {
            reasoningContent = (reasoningContent ?? "") + deltaReasoning
            pendingReasoningContent += deltaReasoning
            reasoningRenderRevision &+= 1
        }
        if let usage = delta.usage {
            lastUsage = usage
        }
        guard shouldFlush(now: now) else { return nil }
        return makeSnapshotAndReset(now: now)
    }

    func flush(now: Date = .now, force: Bool = false) -> StreamingRenderSnapshot? {
        guard force || shouldFlush(now: now) else { return nil }
        return makeSnapshotAndReset(now: now)
    }

    func finalSnapshot() -> StreamingFinalSnapshot {
        StreamingFinalSnapshot(
            content: content,
            reasoningContent: reasoningContent,
            usage: lastUsage
        )
    }

    private func shouldFlush(now: Date) -> Bool {
        guard !pendingContent.isEmpty || !pendingReasoningContent.isEmpty else { return false }
        guard pendingContent.count + pendingReasoningContent.count < maximumBufferedCharacters else {
            return true
        }
        return now.timeIntervalSince(lastFlushDate) >= minimumFlushInterval
    }

    private func makeSnapshotAndReset(now: Date) -> StreamingRenderSnapshot? {
        guard !pendingContent.isEmpty || !pendingReasoningContent.isEmpty else { return nil }
        let blocks = TextContentBlock.makeDisplayBlocks(from: content)
        let displayText = blocks.map(\.text).joined()
        let renderedMarkdown = try? AttributedString(
            markdown: displayText,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )
        pendingContent = ""
        pendingReasoningContent = ""
        lastFlushDate = now
        return StreamingRenderSnapshot(
            messageID: messageID,
            content: content,
            contentBlocks: blocks,
            contentRenderRevision: contentRenderRevision,
            reasoningContent: reasoningContent,
            reasoningRenderRevision: reasoningRenderRevision,
            renderedMarkdown: renderedMarkdown
        )
    }
}

struct StreamingRenderBuffer {
    private let minimumFlushInterval: TimeInterval
    private let maximumBufferedCharacters: Int
    private var lastFlushDate: Date
    private var bufferedContent = ""
    private var bufferedReasoningContent = ""

    init(
        minimumFlushInterval: TimeInterval = 0.05,
        maximumBufferedCharacters: Int = 520,
        now: Date = .now
    ) {
        self.minimumFlushInterval = minimumFlushInterval
        self.maximumBufferedCharacters = maximumBufferedCharacters
        self.lastFlushDate = now
    }

    mutating func append(content: String, reasoningContent: String? = nil) {
        bufferedContent += content
        if let reasoningContent {
            bufferedReasoningContent += reasoningContent
        }
    }

    mutating func flushIfNeeded(now: Date = .now, force: Bool = false) -> StreamingRenderBatch? {
        guard force || shouldFlush(now: now) else { return nil }
        return flush(now: now)
    }

    private func shouldFlush(now: Date) -> Bool {
        guard !bufferedContent.isEmpty || !bufferedReasoningContent.isEmpty else { return false }
        guard bufferedContent.count + bufferedReasoningContent.count < maximumBufferedCharacters else {
            return true
        }
        return now.timeIntervalSince(lastFlushDate) >= minimumFlushInterval
    }

    private mutating func flush(now: Date) -> StreamingRenderBatch? {
        let batch = StreamingRenderBatch(
            content: bufferedContent,
            reasoningContent: bufferedReasoningContent
        )
        guard !batch.isEmpty else { return nil }
        bufferedContent = ""
        bufferedReasoningContent = ""
        lastFlushDate = now
        return batch
    }
}
