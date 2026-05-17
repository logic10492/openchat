import Foundation
import Testing

@testable import OpenChat

@Suite("Background worker")
struct BackgroundWorkerTests {
    @Test func test_workerIsDeterministicAndKeepsSemanticOverImportance() async throws {
        let worker = BackgroundWorker(clock: Self.clock)
        let request = Self.makeRequest()
        let candidates = [
            Self.candidate(id: "memory:important", sourceType: .memory, content: "High importance unrelated memory.", basePriority: 100, relevance: 0.2),
            Self.candidate(id: "memory:semantic", sourceType: .memory, content: "Highly relevant semantic memory.", basePriority: 1, relevance: 0.9),
            Self.candidate(id: "worldBook:lore", sourceType: .worldBook, content: "Relevant lore.", basePriority: 10, relevance: 0.8),
        ]
        let input = BackgroundWorkerInput(
            request: request,
            candidates: candidates,
            policy: BackgroundPolicy.compatibilityDefault(tokenBudget: 1_000)
        )

        let first = try await worker.run(input)
        let second = try await worker.run(input)

        #expect(first == second)
        #expect(first.entries.map(\.id) == ["memory:semantic", "worldBook:lore", "memory:important"])
        #expect(first.diagnostics.selectedIds == first.entries.map(\.id))
    }

    @Test func test_workerAppliesPerSourceLimitBudgetAndDuplicateOmissions() async throws {
        let worker = BackgroundWorker(clock: Self.clock)
        let policy = BackgroundPolicy(
            tokenBudget: 8,
            maxEntries: 5,
            perSourceLimits: [.memory: 1, .worldBook: 5],
            sourceWeights: [.memory: 0, .worldBook: 0],
            duplicationPenalty: 1,
            lowConfidenceThreshold: 0.01
        )
        let candidates = [
            Self.candidate(id: "memory:a", sourceType: .memory, content: "same text", relevance: 0.9),
            Self.candidate(id: "memory:b", sourceType: .memory, content: "same text", relevance: 0.8),
            Self.candidate(id: "worldBook:a", sourceType: .worldBook, content: String(repeating: "lore ", count: 30), relevance: 0.7),
            Self.candidate(id: "worldBook:b", sourceType: .worldBook, content: "short lore", relevance: 0.6),
        ]

        let packet = try await worker.run(
            BackgroundWorkerInput(
                request: Self.makeRequest(),
                candidates: candidates,
                policy: policy
            )
        )

        #expect(packet.entries.map(\.id).contains("memory:a"))
        #expect(packet.omitted.contains { $0.candidateId == "memory:b" && $0.reason == .duplicate })
        #expect(packet.omitted.contains { $0.reason == .budgetExceeded })
        #expect(packet.diagnostics.sourceSummaries.contains { $0.sourceType == .memory && $0.selectedCount == 1 })
    }

    @Test func test_workerDeniesNonDeterministicPolicyWithoutPartialPacket() async throws {
        let worker = BackgroundWorker(clock: Self.clock)
        let deniedPolicy = AgentPolicy(
            allowedCapabilities: [.internalDiagnostics],
            tokenBudget: AgentTokenBudget(maxInputTokens: 10, maxOutputTokens: 0, maxTotalTokens: 10),
            timeoutSeconds: 1,
            retryPolicy: AgentRetryPolicy(maxAttempts: 1, retryDelaySeconds: 0),
            schemaRepairPolicy: SchemaRepairPolicy(allowRepair: false, maxRepairAttempts: 0),
            visibilityPolicy: AgentVisibilityPolicy(exposeDiagnosticsToUser: false, exposeDraftToUser: false),
            toolUsePolicy: .disabled,
            sideEffectPolicy: .readOnly,
            confirmationPolicy: ConfirmationPolicy(requiredForDraftApply: false, requiredForPersistentWrite: true)
        )

        await #expect(throws: AgentError.capabilityDenied(agentId: "background-worker", capability: .deterministic)) {
            try await worker.run(
                BackgroundWorkerInput(
                    request: Self.makeRequest(),
                    candidates: [Self.candidate(id: "memory:a", sourceType: .memory, content: "content")],
                    policy: BackgroundPolicy.compatibilityDefault(),
                    agentPolicy: deniedPolicy
                )
            )
        }
    }

    private static func candidate(
        id: String,
        sourceType: BackgroundSourceType,
        content: String,
        basePriority: Int = 1,
        relevance: Double? = nil
    ) -> BackgroundCandidate {
        BackgroundCandidate(
            id: id,
            sourceType: sourceType,
            sourceId: String(id.split(separator: ":").last ?? "source"),
            content: content,
            title: sourceType == .memory ? "event" : "Lore",
            basePriority: basePriority,
            relevance: relevance,
            recency: Date(timeIntervalSince1970: 1_000),
            metadata: ["reasons": "semantic"]
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
