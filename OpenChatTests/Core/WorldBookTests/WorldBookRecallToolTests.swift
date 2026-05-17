import Foundation
import Testing

@testable import OpenChat

@Suite("WorldBookRecallTool")
struct WorldBookRecallToolTests {
    @Test func test_call_forwards_input_to_worldBookSource() async throws {
        let worldBook = TestHelpers.makeWorldBook(id: "world-forward")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "entry-forward")
        let message = TestHelpers.makeMessage(
            conversationId: "conversation-forward",
            role: "assistant",
            content: "The archive is sealed.",
            sortOrder: 1
        )
        let expected = makeResult(entries: [makeRecallEntry(entry: entry, finalRank: 1)])
        let source = RecordingWorldBookRecallSource(result: expected)
        let tool = WorldBookRecallTool(source: source)

        #expect(tool.sourceType == .worldBook)

        let result = try await tool.call(
            WorldBookRecallToolInput(
                worldBook: worldBook,
                entries: [entry],
                recentMessages: [message],
                currentInput: "open the archive",
                limit: 3
            )
        )

        let calls = await source.calls
        #expect(calls.count == 1)
        #expect(calls.first?.worldBook?.id == worldBook.id)
        #expect(calls.first?.entries.map(\.id) == [entry.id])
        #expect(calls.first?.recentMessages.map(\.id) == [message.id])
        #expect(calls.first?.currentInput == "open the archive")
        #expect(calls.first?.limit == 3)
        #expect(result.entries.map(\.entry.id) == [entry.id])
    }

    @Test func test_keywordOnly_resultOrderAndTrace_arePassedThrough() async throws {
        let worldBook = TestHelpers.makeWorldBook(id: "world-keyword-tool")
        let first = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "keyword-first",
            title: "First",
            keywords: ["first"]
        )
        let second = TestHelpers.makeWorldBookEntry(
            worldBookId: worldBook.id,
            id: "keyword-second",
            title: "Second",
            keywords: ["second"]
        )
        let expected = makeResult(
            entries: [
                makeRecallEntry(
                    entry: first,
                    finalRank: 1,
                    keywordRank: 1,
                    keywordHits: ["first"],
                    reasons: [.keyword]
                ),
                makeRecallEntry(
                    entry: second,
                    finalRank: 2,
                    keywordRank: 2,
                    keywordHits: ["second"],
                    reasons: [.keyword]
                ),
            ],
            keywordCandidateCount: 2,
            selectedIds: [first.id, second.id]
        )

        let result = try await callTool(result: expected, worldBook: worldBook, entries: [second, first])

        #expect(result.entries.map(\.entry.id) == [first.id, second.id])
        #expect(result.entries.map(\.finalRank) == [1, 2])
        #expect(result.entries.map(\.keywordRank) == [1, 2])
        #expect(result.entries.flatMap(\.keywordHits) == ["first", "second"])
        #expect(result.entries.flatMap(\.reasons) == [.keyword, .keyword])
        #expect(result.trace.keywordCandidateCount == 2)
        #expect(result.trace.selectedIds == [first.id, second.id])
    }

    @Test func test_semanticOnly_resultOrderAndTrace_arePassedThrough() async throws {
        let worldBook = TestHelpers.makeWorldBook(id: "world-semantic-tool")
        let first = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "semantic-first")
        let second = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "semantic-second")
        let expected = makeResult(
            entries: [
                makeRecallEntry(
                    entry: first,
                    finalRank: 1,
                    semanticRank: 1,
                    semanticDistance: 0.12,
                    reasons: [.semantic]
                ),
                makeRecallEntry(
                    entry: second,
                    finalRank: 2,
                    semanticRank: 2,
                    semanticDistance: 0.24,
                    reasons: [.semantic]
                ),
            ],
            semanticCandidateCount: 2,
            selectedIds: [first.id, second.id]
        )

        let result = try await callTool(result: expected, worldBook: worldBook, entries: [second, first])

        #expect(result.entries.map(\.entry.id) == [first.id, second.id])
        #expect(result.entries.map(\.semanticRank) == [1, 2])
        #expect(result.entries.map(\.semanticDistance) == [0.12, 0.24])
        #expect(result.entries.flatMap(\.reasons) == [.semantic, .semantic])
        #expect(result.trace.semanticCandidateCount == 2)
        #expect(result.trace.selectedIds == [first.id, second.id])
    }

    @Test func test_hybrid_resultOrderReasonsAndOmissions_arePassedThrough() async throws {
        let worldBook = TestHelpers.makeWorldBook(id: "world-hybrid-tool")
        let hybrid = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "hybrid-entry")
        let keywordOnly = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "keyword-entry")
        let semanticOnly = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "semantic-entry")
        let expected = makeResult(
            entries: [
                makeRecallEntry(
                    entry: hybrid,
                    finalRank: 1,
                    keywordRank: 1,
                    semanticRank: 1,
                    semanticDistance: 0.05,
                    keywordHits: ["hybrid"],
                    reasons: [.keyword, .semantic]
                ),
                makeRecallEntry(
                    entry: keywordOnly,
                    finalRank: 2,
                    keywordRank: 2,
                    keywordHits: ["keyword"],
                    reasons: [.keyword]
                ),
                makeRecallEntry(
                    entry: semanticOnly,
                    finalRank: 3,
                    semanticRank: 2,
                    semanticDistance: 0.18,
                    reasons: [.semantic]
                ),
            ],
            keywordCandidateCount: 2,
            semanticCandidateCount: 2,
            selectedIds: [hybrid.id, keywordOnly.id, semanticOnly.id],
            omissions: [
                WorldBookRecallOmission(entryId: hybrid.id, reason: .duplicate, detail: nil),
                WorldBookRecallOmission(entryId: "overflow-entry", reason: .limitExceeded, detail: nil),
            ]
        )

        let result = try await callTool(
            result: expected,
            worldBook: worldBook,
            entries: [semanticOnly, keywordOnly, hybrid],
            limit: 3
        )

        #expect(result.entries.map(\.entry.id) == [hybrid.id, keywordOnly.id, semanticOnly.id])
        #expect(result.entries.first?.reasons == [.keyword, .semantic])
        #expect(result.entries.first?.keywordRank == 1)
        #expect(result.entries.first?.semanticRank == 1)
        #expect(result.trace.omissions.map(\.reason) == [.duplicate, .limitExceeded])
        #expect(result.trace.omissions.map(\.entryId) == [hybrid.id, "overflow-entry"])
    }

    @Test func test_disabledWorldBookAndEntry_omissionsArePassedThrough() async throws {
        let disabledWorldBook = TestHelpers.makeWorldBook(id: "world-disabled-tool", isEnabled: false)
        var disabledEntry = TestHelpers.makeWorldBookEntry(
            worldBookId: disabledWorldBook.id,
            id: "disabled-entry"
        )
        disabledEntry.isEnabled = false
        let expected = makeResult(
            entries: [],
            selectedIds: [],
            omissions: [
                WorldBookRecallOmission(entryId: disabledEntry.id, reason: .disabled, detail: nil),
            ]
        )

        let result = try await callTool(
            result: expected,
            worldBook: disabledWorldBook,
            entries: [disabledEntry]
        )

        #expect(result.entries.isEmpty)
        #expect(result.trace.omissions.count == 1)
        #expect(result.trace.omissions.first?.entryId == disabledEntry.id)
        #expect(result.trace.omissions.first?.reason == .disabled)
    }

    @Test func test_semanticUnavailableFallbackTrace_isPassedThrough() async throws {
        let worldBook = TestHelpers.makeWorldBook(id: "world-fallback-tool")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "fallback-entry")
        let expected = makeResult(
            entries: [
                makeRecallEntry(
                    entry: entry,
                    finalRank: 1,
                    keywordRank: 1,
                    keywordHits: ["fallback"],
                    reasons: [.keyword]
                ),
            ],
            keywordCandidateCount: 1,
            semanticCandidateCount: 0,
            selectedIds: [entry.id],
            omissions: [
                WorldBookRecallOmission(
                    entryId: nil,
                    reason: .semanticUnavailable,
                    detail: "forced semantic failure"
                ),
            ]
        )

        let result = try await callTool(result: expected, worldBook: worldBook, entries: [entry])

        #expect(result.entries.map(\.entry.id) == [entry.id])
        #expect(result.entries.first?.reasons == [.keyword])
        #expect(result.trace.omissions.first?.entryId == nil)
        #expect(result.trace.omissions.first?.reason == .semanticUnavailable)
        #expect(result.trace.omissions.first?.detail == "forced semantic failure")
    }

    @Test func test_staleEmbeddingTrace_isPassedThrough() async throws {
        let worldBook = TestHelpers.makeWorldBook(id: "world-stale-tool")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "selected-entry")
        let expected = makeResult(
            entries: [makeRecallEntry(entry: entry, finalRank: 1, semanticRank: 1, reasons: [.semantic])],
            semanticCandidateCount: 2,
            selectedIds: [entry.id],
            omissions: [
                WorldBookRecallOmission(entryId: "deleted-entry", reason: .staleEmbedding, detail: nil),
            ]
        )

        let result = try await callTool(result: expected, worldBook: worldBook, entries: [entry])

        #expect(result.entries.map(\.entry.id) == [entry.id])
        #expect(result.trace.omissions.first?.entryId == "deleted-entry")
        #expect(result.trace.omissions.first?.reason == .staleEmbedding)
    }

    @Test func test_toolOnlyCallsRecallSourceOnce_withoutIndexerOrRebuildDependency() async throws {
        let worldBook = TestHelpers.makeWorldBook(id: "world-readonly-tool")
        let entry = TestHelpers.makeWorldBookEntry(worldBookId: worldBook.id, id: "readonly-entry")
        let expected = makeResult(entries: [makeRecallEntry(entry: entry, finalRank: 1)])
        let source = RecordingWorldBookRecallSource(result: expected)
        let tool = WorldBookRecallTool(source: source)

        _ = try await tool.call(
            WorldBookRecallToolInput(
                worldBook: worldBook,
                entries: [entry],
                recentMessages: [],
                currentInput: "readonly",
                limit: 1
            )
        )

        #expect(await source.callCount == 1)
    }

    private func callTool(
        result expected: WorldBookRecallResult,
        worldBook: WorldBookRecord,
        entries: [WorldBookEntryRecord],
        limit: Int = 5
    ) async throws -> WorldBookRecallResult {
        let source = RecordingWorldBookRecallSource(result: expected)
        let tool = WorldBookRecallTool(source: source)
        return try await tool.call(
            WorldBookRecallToolInput(
                worldBook: worldBook,
                entries: entries,
                recentMessages: [],
                currentInput: "current input",
                limit: limit
            )
        )
    }

    private func makeResult(
        entries: [WorldBookRecallEntry],
        keywordCandidateCount: Int = 0,
        semanticCandidateCount: Int = 0,
        selectedIds: [String]? = nil,
        omissions: [WorldBookRecallOmission] = []
    ) -> WorldBookRecallResult {
        WorldBookRecallResult(
            entries: entries,
            trace: WorldBookRecallTrace(
                querySummary: "tool-pass-through-query",
                keywordCandidateCount: keywordCandidateCount,
                semanticCandidateCount: semanticCandidateCount,
                selectedIds: selectedIds ?? entries.map(\.entry.id),
                omissions: omissions
            )
        )
    }

    private func makeRecallEntry(
        entry: WorldBookEntryRecord,
        finalRank: Int,
        keywordRank: Int? = nil,
        semanticRank: Int? = nil,
        semanticDistance: Float? = nil,
        keywordHits: [String] = [],
        reasons: [WorldBookRecallReason] = [.keyword]
    ) -> WorldBookRecallEntry {
        WorldBookRecallEntry(
            entry: entry,
            finalRank: finalRank,
            keywordRank: keywordRank,
            semanticRank: semanticRank,
            semanticDistance: semanticDistance,
            keywordHits: keywordHits,
            reasons: reasons
        )
    }
}

private actor RecordingWorldBookRecallSource: WorldBookRecallSource {
    private(set) var calls: [WorldBookRecallToolInput] = []
    private let result: WorldBookRecallResult

    var callCount: Int {
        calls.count
    }

    init(result: WorldBookRecallResult) {
        self.result = result
    }

    func recallEntries(
        worldBook: WorldBookRecord?,
        entries: [WorldBookEntryRecord],
        recentMessages: [MessageRecord],
        currentInput: String,
        limit: Int
    ) async throws -> WorldBookRecallResult {
        calls.append(
            WorldBookRecallToolInput(
                worldBook: worldBook,
                entries: entries,
                recentMessages: recentMessages,
                currentInput: currentInput,
                limit: limit
            )
        )
        return result
    }
}
