import Foundation
import Testing

@testable import OpenChat

private actor BackgroundMemoryRecallRecorder {
    private(set) var calls: [MemoryRecallToolInput] = []
    private let result: MemoryRecallResult

    init(result: MemoryRecallResult) {
        self.result = result
    }

    func recall(
        characterCardId: String,
        query: String,
        limit: Int
    ) async throws -> MemoryRecallResult {
        calls.append(
            MemoryRecallToolInput(
                characterCardId: characterCardId,
                query: query,
                limit: limit
            )
        )
        return result
    }
}

private actor BackgroundWorldBookRecallRecorder {
    private(set) var calls: [WorldBookRecallToolInput] = []
    private let resultFactory: @Sendable (
        _ worldBook: WorldBookRecord?,
        _ entries: [WorldBookEntryRecord],
        _ recentMessages: [MessageRecord],
        _ currentInput: String,
        _ limit: Int
    ) -> WorldBookRecallResult

    init(resultFactory: @escaping @Sendable (
        _ worldBook: WorldBookRecord?,
        _ entries: [WorldBookEntryRecord],
        _ recentMessages: [MessageRecord],
        _ currentInput: String,
        _ limit: Int
    ) -> WorldBookRecallResult) {
        self.resultFactory = resultFactory
    }

    func recall(
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
        return resultFactory(worldBook, entries, recentMessages, currentInput, limit)
    }
}

private actor BackgroundCallFlag {
    private(set) var didCall = false

    func markCalled() {
        didCall = true
    }
}

@Suite("Background source adapters")
struct BackgroundSourceTests {
    @Test func test_memoryCandidates_preserveRecallOrderAndMetadata() {
        let memories = [
            Self.makeMemory(id: "mem-a", content: "semantic first", importance: 10, updatedAt: Self.date(10)),
            Self.makeMemory(id: "mem-b", content: "keyword second", importance: 90, updatedAt: Self.date(20)),
            Self.makeMemory(id: "mem-c", content: "recent third", importance: 70, updatedAt: Self.date(30)),
        ]
        let result = MemoryRecallResult(
            entries: [
                MemoryRecallEntry(
                    memory: memories[0],
                    finalRank: 1,
                    semanticRank: 1,
                    semanticDistance: 0.2,
                    keywordRank: nil,
                    recencyRank: nil,
                    reasons: [.semantic]
                ),
                MemoryRecallEntry(
                    memory: memories[1],
                    finalRank: 2,
                    semanticRank: nil,
                    semanticDistance: nil,
                    keywordRank: 1,
                    recencyRank: nil,
                    reasons: [.keyword]
                ),
                MemoryRecallEntry(
                    memory: memories[2],
                    finalRank: 3,
                    semanticRank: nil,
                    semanticDistance: nil,
                    keywordRank: nil,
                    recencyRank: 1,
                    reasons: [.recentHighValue]
                ),
            ],
            trace: MemoryRecallTrace(
                query: "forest promise",
                semanticCandidateCount: 1,
                keywordCandidateCount: 1,
                recentCandidateCount: 1,
                selectedIds: ["mem-a", "mem-b", "mem-c"],
                omitted: [
                    MemoryRecallOmission(memoryId: "mem-z", reason: .limitExceeded),
                ],
                fallback: .semanticUnavailable
            )
        )

        let candidates = MemoryBackgroundSource.candidates(from: result)

        #expect(candidates.map { $0.id } == ["memory:mem-a", "memory:mem-b", "memory:mem-c"])
        #expect(candidates.map { $0.sourceId } == ["mem-a", "mem-b", "mem-c"])
        #expect(candidates.map { $0.content } == ["semantic first", "keyword second", "recent third"])
        #expect(candidates.map { $0.basePriority } == [10, 90, 70])
        #expect(candidates[0].sourceType == BackgroundSourceType.memory)
        #expect(candidates[0].title == MemoryType.event.rawValue)
        #expect(candidates[0].relevance == 1)
        #expect(candidates[0].recency == Self.date(10))
        #expect(candidates[0].metadata["semanticRank"] == "1")
        #expect(candidates[0].metadata["semanticDistance"] == "0.2")
        #expect(candidates[1].metadata["keywordRank"] == "1")
        #expect(candidates[2].metadata["recencyRank"] == "1")
        #expect(candidates[0].metadata["fallback"] == MemoryRecallFallback.semanticUnavailable.rawValue)
        #expect(candidates[0].metadata["omittedIds"] == "mem-z")
        #expect(candidates[0].metadata["omissionReasons"] == MemoryRecallOmissionReason.limitExceeded.rawValue)
    }

    @Test func test_memorySource_usesCharacterBoundaryAndDoesNotTrimByTokenBudget() async throws {
        let result = MemoryRecallResult(
            entries: [
                MemoryRecallEntry(
                    memory: Self.makeMemory(id: "mem-1", importance: 1),
                    finalRank: 1,
                    semanticRank: 1,
                    semanticDistance: 0.1,
                    keywordRank: nil,
                    recencyRank: nil,
                    reasons: [.semantic]
                ),
                MemoryRecallEntry(
                    memory: Self.makeMemory(id: "mem-2", importance: 2),
                    finalRank: 2,
                    semanticRank: 2,
                    semanticDistance: 0.2,
                    keywordRank: nil,
                    recencyRank: nil,
                    reasons: [.semantic]
                ),
            ],
            trace: MemoryRecallTrace(
                query: "current input",
                semanticCandidateCount: 2,
                keywordCandidateCount: 0,
                recentCandidateCount: 0,
                selectedIds: ["mem-1", "mem-2"],
                omitted: [],
                fallback: nil
            )
        )
        let recorder = BackgroundMemoryRecallRecorder(result: result)
        let source = MemoryBackgroundSource { characterCardId, query, limit in
            try await recorder.recall(characterCardId: characterCardId, query: query, limit: limit)
        }
        let request = Self.makeRequest(characterCard: TestHelpers.makeCharacterCard(id: "character-1"), tokenBudget: 1, memoryLimit: 2)

        let candidates = try await source.candidates(for: request)
        let calls = await recorder.calls

        #expect(calls.map { $0.characterCardId } == ["character-1"])
        #expect(calls.map { $0.query } == ["current input"])
        #expect(calls.map { $0.limit } == [2])
        #expect(candidates.map { $0.id } == ["memory:mem-1", "memory:mem-2"])
    }

    @Test func test_memorySource_withoutCharacterDoesNotCallRecall() async throws {
        let flag = BackgroundCallFlag()
        let source = MemoryBackgroundSource { _, _, _ in
            await flag.markCalled()
            return MemoryRecallResult(
                entries: [],
                trace: MemoryRecallTrace(
                    query: "",
                    semanticCandidateCount: 0,
                    keywordCandidateCount: 0,
                    recentCandidateCount: 0,
                    selectedIds: [],
                    omitted: [],
                    fallback: .emptyIndex
                )
            )
        }

        let candidates = try await source.candidates(for: Self.makeRequest(characterCard: nil))

        #expect(candidates.isEmpty)
        #expect(await flag.didCall == false)
    }

    @Test func test_worldBookCandidates_preserveRecallOrderAndMetadata() {
        let entries = [
            Self.makeWorldBookEntry(id: "wb-a", title: "Semantic", priority: 10, content: "semantic lore", updatedAt: Self.date(10)),
            Self.makeWorldBookEntry(id: "wb-b", title: "Keyword", priority: 100, content: "keyword lore", updatedAt: Self.date(20)),
            Self.makeWorldBookEntry(id: "wb-c", title: "Hybrid", priority: 50, content: "hybrid lore", updatedAt: Self.date(30)),
        ]
        let result = WorldBookRecallResult(
            entries: [
                WorldBookRecallEntry(
                    entry: entries[0],
                    finalRank: 1,
                    keywordRank: nil,
                    semanticRank: 1,
                    semanticDistance: 0.3,
                    keywordHits: [],
                    reasons: [.semantic]
                ),
                WorldBookRecallEntry(
                    entry: entries[1],
                    finalRank: 2,
                    keywordRank: 1,
                    semanticRank: nil,
                    semanticDistance: nil,
                    keywordHits: ["gate", "king"],
                    reasons: [.keyword]
                ),
                WorldBookRecallEntry(
                    entry: entries[2],
                    finalRank: 3,
                    keywordRank: 2,
                    semanticRank: 2,
                    semanticDistance: 0.4,
                    keywordHits: ["forest"],
                    reasons: [.keyword, .semantic]
                ),
            ],
            trace: WorldBookRecallTrace(
                querySummary: "world query",
                keywordCandidateCount: 2,
                semanticCandidateCount: 2,
                selectedIds: ["wb-a", "wb-b", "wb-c"],
                omissions: [
                    WorldBookRecallOmission(entryId: "wb-z", reason: .duplicate, detail: nil),
                    WorldBookRecallOmission(entryId: nil, reason: .semanticUnavailable, detail: "model unavailable"),
                ]
            )
        )

        let candidates = WorldBookBackgroundSource.candidates(from: result)

        #expect(candidates.map { $0.id } == ["worldBook:wb-a", "worldBook:wb-b", "worldBook:wb-c"])
        #expect(candidates.map { $0.sourceId } == ["wb-a", "wb-b", "wb-c"])
        #expect(candidates.map { $0.content } == ["semantic lore", "keyword lore", "hybrid lore"])
        #expect(candidates.map { $0.basePriority } == [10, 100, 50])
        #expect(candidates[0].sourceType == BackgroundSourceType.worldBook)
        #expect(candidates[0].title == "Semantic")
        #expect(candidates[0].relevance == 1)
        #expect(candidates[0].recency == Self.date(10))
        #expect(candidates[0].metadata["semanticRank"] == "1")
        #expect(candidates[0].metadata["semanticDistance"] == "0.3")
        #expect(candidates[1].metadata["keywordRank"] == "1")
        #expect(candidates[1].metadata["keywordHits"] == "gate,king")
        #expect(candidates[2].metadata["reasons"] == "keyword,semantic")
        #expect(candidates[0].metadata["fallback"] == WorldBookRecallOmissionReason.semanticUnavailable.rawValue)
        #expect(candidates[0].metadata["omittedIds"] == "wb-z")
        #expect(candidates[0].metadata["omissionReasons"] == "duplicate,semanticUnavailable")
        #expect(candidates[0].metadata["omissionDetails"] == "model unavailable")
    }

    @Test func test_worldBookSource_passesNilWorldBookAndDoesNotTrimByTokenBudget() async throws {
        let recorder = BackgroundWorldBookRecallRecorder { _, entries, _, currentInput, _ in
            WorldBookRecallResult(
                entries: entries.enumerated().map { index, entry in
                    WorldBookRecallEntry(
                        entry: entry,
                        finalRank: index + 1,
                        keywordRank: index + 1,
                        semanticRank: nil,
                        semanticDistance: nil,
                        keywordHits: ["key-\(index + 1)"],
                        reasons: [.keyword]
                    )
                },
                trace: WorldBookRecallTrace(
                    querySummary: currentInput,
                    keywordCandidateCount: entries.count,
                    semanticCandidateCount: 0,
                    selectedIds: entries.map { $0.id },
                    omissions: [
                        WorldBookRecallOmission(entryId: entries.first?.id, reason: .disabled, detail: nil),
                    ]
                )
            )
        }
        let source = WorldBookBackgroundSource { worldBook, entries, recentMessages, currentInput, limit in
            try await recorder.recall(
                worldBook: worldBook,
                entries: entries,
                recentMessages: recentMessages,
                currentInput: currentInput,
                limit: limit
            )
        }
        let request = Self.makeRequest(
            worldBook: nil,
            worldBookEntries: [
                Self.makeWorldBookEntry(id: "wb-1"),
                Self.makeWorldBookEntry(id: "wb-2"),
            ],
            tokenBudget: 1,
            worldBookLimit: 2
        )

        let candidates = try await source.candidates(for: request)
        let calls = await recorder.calls

        #expect(calls.first?.worldBook == nil)
        #expect(calls.first?.entries.map { $0.id } == ["wb-1", "wb-2"])
        #expect(calls.first?.recentMessages.count == 1)
        #expect(calls.first?.currentInput == "current input")
        #expect(calls.first?.limit == 2)
        #expect(candidates.map { $0.id } == ["worldBook:wb-1", "worldBook:wb-2"])
    }

    @Test func test_sourceTypeContract_exposesReadOnlySourceKinds() {
        let diagnostics = BackgroundToolDiagnostics(
            sourceType: .memory,
            inputSummary: ["queryLength": "13"],
            startedAt: Self.date(1),
            durationMilliseconds: nil,
            fallback: MemoryRecallFallback.noSemanticHit.rawValue
        )

        #expect(BackgroundSourceType.memory.rawValue == "memory")
        #expect(BackgroundSourceType.worldBook.rawValue == "worldBook")
        #expect(diagnostics.sourceType == .memory)
        #expect(diagnostics.durationMilliseconds == nil)
        #expect(diagnostics.fallback == MemoryRecallFallback.noSemanticHit.rawValue)
    }

    private static func makeRequest(
        characterCard: CharacterCardRecord? = TestHelpers.makeCharacterCard(id: "character-1"),
        worldBook: WorldBookRecord? = TestHelpers.makeWorldBook(id: "world-book-1"),
        worldBookEntries: [WorldBookEntryRecord] = [],
        tokenBudget: Int = 1024,
        memoryLimit: Int = 10,
        worldBookLimit: Int = 10
    ) -> BackgroundRequest {
        BackgroundRequest(
            conversation: TestHelpers.makeConversation(id: "conversation-1"),
            characterCard: characterCard,
            worldBook: worldBook,
            worldBookEntries: worldBookEntries,
            recentMessages: [
                TestHelpers.makeMessage(
                    conversationId: "conversation-1",
                    role: "user",
                    content: "recent context",
                    sortOrder: 1
                ),
            ],
            currentInput: "current input",
            tokenBudget: tokenBudget,
            memoryLimit: memoryLimit,
            worldBookLimit: worldBookLimit
        )
    }

    private static func makeMemory(
        id: String,
        content: String = "memory",
        importance: Int,
        updatedAt: Date = Self.date(100)
    ) -> MemoryEntryRecord {
        MemoryEntryRecord(
            id: id,
            characterCardId: "character-1",
            sourceConversationId: nil,
            content: content,
            memoryType: MemoryType.event.rawValue,
            importance: importance,
            createdAt: Self.date(0),
            updatedAt: updatedAt
        )
    }

    private static func makeWorldBookEntry(
        id: String,
        title: String = "World Entry",
        priority: Int = 50,
        content: String = "world content",
        updatedAt: Date = Self.date(100)
    ) -> WorldBookEntryRecord {
        WorldBookEntryRecord(
            id: id,
            worldBookId: "world-book-1",
            title: title,
            content: content,
            keywords: #"["world"]"#,
            priority: priority,
            isEnabled: true,
            position: WorldBookEntryPosition.beforeHistory.rawValue,
            createdAt: Self.date(0),
            updatedAt: updatedAt
        )
    }

    private static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
