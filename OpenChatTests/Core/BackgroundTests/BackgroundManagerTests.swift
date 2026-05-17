import Foundation
import Testing

@testable import OpenChat

private struct StubBackgroundSource: BackgroundSource {
    let sourceType: BackgroundSourceType
    let candidatesResult: [BackgroundCandidate]

    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate] {
        candidatesResult
    }
}

private struct FailingBackgroundSource: BackgroundSource {
    let sourceType: BackgroundSourceType

    func candidates(for request: BackgroundRequest) async throws -> [BackgroundCandidate] {
        throw TestError.sourceFailed
    }
}

private enum TestError: LocalizedError {
    case sourceFailed

    var errorDescription: String? {
        "forced source failure"
    }
}

@Suite("Background manager")
struct BackgroundManagerTests {
    @Test func test_prepareMergesSourcesAndRunsWorker() async throws {
        let manager = BackgroundManager(
            sources: [
                StubBackgroundSource(sourceType: .memory, candidatesResult: [
                    Self.candidate(id: "memory:a", sourceType: .memory, content: "memory", relevance: 0.9),
                ]),
                StubBackgroundSource(sourceType: .worldBook, candidatesResult: [
                    Self.candidate(id: "worldBook:a", sourceType: .worldBook, content: "lore", relevance: 0.8),
                ]),
            ],
            worker: BackgroundWorker(clock: Self.clock)
        )

        let packet = try await manager.prepare(
            request: Self.makeRequest(),
            policy: BackgroundPolicy.compatibilityDefault()
        )

        #expect(packet.entries.map(\.id).contains("memory:a"))
        #expect(packet.entries.map(\.id).contains("worldBook:a"))
        #expect(packet.diagnostics.sourceSummaries.contains { $0.sourceType == .memory && $0.candidateCount == 1 })
        #expect(packet.diagnostics.sourceSummaries.contains { $0.sourceType == .worldBook && $0.candidateCount == 1 })
    }

    @Test func test_prepareFallsBackToPreselectedWorldBookEntriesWhenWorldBookSourceFails() async throws {
        let fallbackEntry = TestHelpers.makeWorldBookEntry(
            worldBookId: "world-book-1",
            id: "fallback-entry",
            title: "Fallback Lore",
            keywords: ["fallback"],
            content: "Fallback world-book lore."
        )
        let manager = BackgroundManager(
            sources: [
                FailingBackgroundSource(sourceType: .worldBook),
            ],
            worker: BackgroundWorker(clock: Self.clock)
        )

        let packet = try await manager.prepare(
            request: Self.makeRequest(worldBookEntries: [fallbackEntry], currentInput: "Use fallback now."),
            policy: BackgroundPolicy.compatibilityDefault()
        )

        #expect(packet.entries.map(\.id) == ["worldBook:fallback-entry"])
        #expect(packet.entries.first?.metadata["fallback"] == "sourceError")
        #expect(packet.diagnostics.warnings.contains { $0.contains("worldBook source failed") })
    }

    private static func candidate(
        id: String,
        sourceType: BackgroundSourceType,
        content: String,
        relevance: Double
    ) -> BackgroundCandidate {
        BackgroundCandidate(
            id: id,
            sourceType: sourceType,
            sourceId: String(id.split(separator: ":").last ?? "source"),
            content: content,
            title: sourceType == .memory ? "event" : "Lore",
            basePriority: 10,
            relevance: relevance,
            recency: nil,
            metadata: ["reasons": "semantic"]
        )
    }

    private static func makeRequest(
        worldBookEntries: [WorldBookEntryRecord] = [],
        currentInput: String = "current input"
    ) -> BackgroundRequest {
        BackgroundRequest(
            conversation: TestHelpers.makeConversation(id: "conversation-1"),
            characterCard: TestHelpers.makeCharacterCard(id: "character-1"),
            worldBook: TestHelpers.makeWorldBook(id: "world-book-1"),
            worldBookEntries: worldBookEntries,
            recentMessages: [],
            currentInput: currentInput,
            tokenBudget: 1_000
        )
    }

    private static func clock() -> Date {
        Date(timeIntervalSince1970: 1_000)
    }
}
