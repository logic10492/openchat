import Foundation
import Testing

@testable import OpenChat

private actor RecordingMemoryRecallProvider: MemoryRecallProviding {
    private var calls: [MemoryRecallToolInput] = []
    private let result: MemoryRecallResult

    init(result: MemoryRecallResult) {
        self.result = result
    }

    func recallMemories(
        for characterCardId: String,
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

    func recordedCalls() -> [MemoryRecallToolInput] {
        calls
    }
}

@Suite("MemoryRecallTool")
struct MemoryRecallToolTests {
    @Test func test_call_forwards_input_and_preserves_result_order_and_metadata() async throws {
        let expectedResult = MemoryRecallResult(
            entries: [
                Self.makeRecallEntry(
                    id: "memory-semantic",
                    finalRank: 1,
                    semanticRank: 1,
                    semanticDistance: 0.12,
                    keywordRank: nil,
                    recencyRank: 2,
                    reasons: [.semantic, .recentHighValue]
                ),
                Self.makeRecallEntry(
                    id: "memory-keyword",
                    finalRank: 2,
                    semanticRank: nil,
                    semanticDistance: nil,
                    keywordRank: 1,
                    recencyRank: nil,
                    reasons: [.keyword]
                ),
                Self.makeRecallEntry(
                    id: "memory-recent",
                    finalRank: 3,
                    semanticRank: nil,
                    semanticDistance: nil,
                    keywordRank: nil,
                    recencyRank: 1,
                    reasons: [.recentHighValue]
                ),
            ],
            trace: MemoryRecallTrace(
                query: "silver key",
                semanticCandidateCount: 4,
                keywordCandidateCount: 2,
                recentCandidateCount: 1,
                selectedIds: ["memory-semantic", "memory-keyword", "memory-recent"],
                omitted: [
                    MemoryRecallOmission(
                        memoryId: "memory-too-far",
                        reason: .distanceThreshold
                    ),
                    MemoryRecallOmission(
                        memoryId: "memory-duplicate",
                        reason: .duplicate
                    ),
                ],
                fallback: .semanticUnavailable
            )
        )
        let provider = RecordingMemoryRecallProvider(result: expectedResult)
        let tool = MemoryRecallTool(provider: provider)

        #expect(tool.sourceType == .memory)

        let result = try await tool.call(
            MemoryRecallToolInput(
                characterCardId: "card-1",
                query: "silver key",
                limit: 3
            )
        )

        #expect(await provider.recordedCalls() == [
            MemoryRecallToolInput(
                characterCardId: "card-1",
                query: "silver key",
                limit: 3
            ),
        ])
        #expect(result.entries.map(\.memory.id) == ["memory-semantic", "memory-keyword", "memory-recent"])
        #expect(result.entries.map(\.finalRank) == [1, 2, 3])
        #expect(result.entries[0].semanticRank == 1)
        #expect(result.entries[0].semanticDistance == 0.12)
        #expect(result.entries[0].recencyRank == 2)
        #expect(result.entries[0].reasons == [.semantic, .recentHighValue])
        #expect(result.entries[1].keywordRank == 1)
        #expect(result.entries[1].reasons == [.keyword])
        #expect(result.entries[2].recencyRank == 1)
        #expect(result.entries[2].reasons == [.recentHighValue])
        #expect(result.trace.selectedIds == ["memory-semantic", "memory-keyword", "memory-recent"])
        #expect(result.trace.semanticCandidateCount == 4)
        #expect(result.trace.keywordCandidateCount == 2)
        #expect(result.trace.recentCandidateCount == 1)
        #expect(result.trace.omitted.map(\.memoryId) == ["memory-too-far", "memory-duplicate"])
        #expect(result.trace.omitted.map(\.reason) == [.distanceThreshold, .duplicate])
        #expect(result.trace.fallback == .semanticUnavailable)
    }

    @Test func test_call_limit_zero_passes_through_empty_recall_result() async throws {
        let expectedResult = MemoryRecallResult(
            entries: [],
            trace: MemoryRecallTrace(
                query: "anything",
                semanticCandidateCount: 0,
                keywordCandidateCount: 0,
                recentCandidateCount: 0,
                selectedIds: [],
                omitted: [],
                fallback: .emptyIndex
            )
        )
        let provider = RecordingMemoryRecallProvider(result: expectedResult)
        let tool = MemoryRecallTool(provider: provider)

        let result = try await tool.call(
            MemoryRecallToolInput(
                characterCardId: "card-empty",
                query: "anything",
                limit: 0
            )
        )

        #expect(await provider.recordedCalls() == [
            MemoryRecallToolInput(
                characterCardId: "card-empty",
                query: "anything",
                limit: 0
            ),
        ])
        #expect(result.entries.isEmpty)
        #expect(result.trace.selectedIds.isEmpty)
        #expect(result.trace.omitted.isEmpty)
        #expect(result.trace.fallback == .emptyIndex)
    }

    private static func makeRecallEntry(
        id: String,
        finalRank: Int,
        semanticRank: Int?,
        semanticDistance: Float?,
        keywordRank: Int?,
        recencyRank: Int?,
        reasons: [MemoryRecallReason]
    ) -> MemoryRecallEntry {
        MemoryRecallEntry(
            memory: MemoryEntryRecord(
                id: id,
                characterCardId: "card-1",
                sourceConversationId: "conversation-1",
                content: "Memory content for \(id)",
                memoryType: MemoryType.event.rawValue,
                importance: 50,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            finalRank: finalRank,
            semanticRank: semanticRank,
            semanticDistance: semanticDistance,
            keywordRank: keywordRank,
            recencyRank: recencyRank,
            reasons: reasons
        )
    }
}
