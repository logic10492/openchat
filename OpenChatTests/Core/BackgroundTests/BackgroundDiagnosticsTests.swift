import Foundation
import Testing

@testable import OpenChat

@Suite("Background diagnostics")
struct BackgroundDiagnosticsTests {
    @Test func test_workerDiagnosticsMirrorPacketSelection() async throws {
        let worker = BackgroundWorker(clock: Self.clock)
        let candidates = [
            Self.candidate(id: "worldBook:a", sourceType: .worldBook, content: "Lore", fallback: "semanticUnavailable"),
            Self.candidate(id: "memory:a", sourceType: .memory, content: "Memory"),
        ]

        let packet = try await worker.run(
            BackgroundWorkerInput(
                request: Self.makeRequest(),
                candidates: candidates,
                policy: BackgroundPolicy.compatibilityDefault()
            )
        )

        #expect(packet.diagnostics.requestId == "conversation-1")
        #expect(packet.diagnostics.selectedIds == packet.entries.map(\.id))
        #expect(packet.diagnostics.inputCandidateCount == 2)
        #expect(packet.diagnostics.elapsedMilliseconds == 0)
        #expect(packet.diagnostics.fallbacks.contains("worldBook:semanticUnavailable"))
        #expect(packet.diagnostics.sourceSummaries.contains { $0.sourceType == .worldBook && $0.candidateCount == 1 })
        #expect(!packet.entries.contains { $0.content.contains("[World Book Entries]") || $0.content.contains("[Memories]") })
    }

    private static func candidate(
        id: String,
        sourceType: BackgroundSourceType,
        content: String,
        fallback: String? = nil
    ) -> BackgroundCandidate {
        var metadata = ["reasons": "semantic"]
        metadata["fallback"] = fallback
        return BackgroundCandidate(
            id: id,
            sourceType: sourceType,
            sourceId: String(id.split(separator: ":").last ?? "source"),
            content: content,
            title: sourceType == .memory ? "event" : "Lore",
            basePriority: 10,
            relevance: 0.8,
            recency: nil,
            metadata: metadata
        )
    }

    private static func makeRequest() -> BackgroundRequest {
        BackgroundRequest(
            conversation: TestHelpers.makeConversation(id: "conversation-1"),
            characterCard: TestHelpers.makeCharacterCard(id: "character-1"),
            worldBook: TestHelpers.makeWorldBook(id: "world-book-1"),
            worldBookEntries: [],
            recentMessages: [],
            currentInput: "current input",
            tokenBudget: 1_000
        )
    }

    private static func clock() -> Date {
        Date(timeIntervalSince1970: 1_000)
    }
}
