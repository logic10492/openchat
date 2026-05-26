import Foundation

struct StreamingRenderBatch: Equatable {
    let content: String
    let reasoningContent: String

    var isEmpty: Bool {
        content.isEmpty && reasoningContent.isEmpty
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
