import Foundation

protocol WorldBookRecallSource: Sendable {
    func recallEntries(
        worldBook: WorldBookRecord?,
        entries: [WorldBookEntryRecord],
        recentMessages: [MessageRecord],
        currentInput: String,
        limit: Int
    ) async throws -> WorldBookRecallResult
}

struct WorldBookRecallToolInput: Sendable {
    let worldBook: WorldBookRecord?
    let entries: [WorldBookEntryRecord]
    let recentMessages: [MessageRecord]
    let currentInput: String
    let limit: Int
}

struct WorldBookRecallTool: BackgroundSourceTool {
    private let source: any WorldBookRecallSource

    let sourceType: BackgroundSourceType = .worldBook

    init(source: any WorldBookRecallSource) {
        self.source = source
    }

    func call(_ input: WorldBookRecallToolInput) async throws -> WorldBookRecallResult {
        try await source.recallEntries(
            worldBook: input.worldBook,
            entries: input.entries,
            recentMessages: input.recentMessages,
            currentInput: input.currentInput,
            limit: input.limit
        )
    }
}

extension WorldBookSource: WorldBookRecallSource {}
