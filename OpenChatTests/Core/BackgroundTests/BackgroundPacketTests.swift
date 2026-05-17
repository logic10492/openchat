import Foundation
import Testing

@testable import OpenChat

@Suite("Background packet DTOs")
struct BackgroundPacketTests {
    @Test func test_defaultPolicyExposesCompatibilityLimits() {
        let policy = BackgroundPolicy.compatibilityDefault(tokenBudget: 512)

        #expect(policy.tokenBudget == 512)
        #expect(policy.maxEntries == 20)
        #expect(policy.limit(for: .memory) == 10)
        #expect(policy.limit(for: .worldBook) == 10)
        #expect(policy.weight(for: .worldBook) > 0)
        #expect(policy.weight(for: .memory) > 0)
        #expect(policy.profile["tokenBudget"] == "512")
    }

    @Test func test_packetPreservesEntryIdentityAndMetadata() {
        let entry = BackgroundEntry(
            id: "memory:1",
            sourceType: .memory,
            sourceId: "1",
            title: "event",
            content: "Remembered promise.",
            rank: 1,
            score: 0.9,
            estimatedTokens: 4,
            reason: "semantic",
            metadata: ["memoryType": "event"]
        )
        let omission = BackgroundOmission(
            id: "memory:2:duplicate",
            candidateId: "memory:2",
            sourceType: .memory,
            reason: .duplicate,
            detail: "Duplicate of memory:1."
        )
        let diagnostics = BackgroundDiagnostics(
            requestId: "conversation-1",
            startedAt: Date(timeIntervalSince1970: 1),
            endedAt: Date(timeIntervalSince1970: 2),
            elapsedMilliseconds: 1_000,
            policyProfile: ["profile": "compat"],
            agentPolicySummary: ["capabilities": "deterministic"],
            sourceSummaries: [],
            inputCandidateCount: 2,
            selectedIds: [entry.id],
            omitted: [omission],
            fallbacks: [],
            warnings: []
        )
        let packet = BackgroundPacket(entries: [entry], omitted: [omission], diagnostics: diagnostics)

        #expect(packet.entries.first?.id == "memory:1")
        #expect(packet.entries.first?.metadata["memoryType"] == "event")
        #expect(packet.omitted.first?.reason == .duplicate)
        #expect(BackgroundOmissionReason.allCases.contains(.budgetExceeded))
    }
}
