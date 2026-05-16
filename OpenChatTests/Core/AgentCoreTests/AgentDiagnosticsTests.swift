import Foundation
import Testing

@testable import OpenChat

@Suite("Agent diagnostics")
struct AgentDiagnosticsTests {
    @Test func test_diagnostics_recordsSelectionOmissionFallbackToolsTokensSchemaAndErrors() {
        let descriptor = AgentDescriptor(
            id: "diagnostics.agent",
            kind: .backgroundWorker,
            displayName: "Diagnostics Agent",
            version: "1.0.0",
            purpose: "Exercises diagnostics shape."
        )
        let policy = AgentPolicy.backgroundWorkerDefault()
        let started = Date(timeIntervalSince1970: 100)
        let ended = Date(timeIntervalSince1970: 101)

        let diagnostics = AgentDiagnostics.make(
            taskName: "DiagnosticsTask",
            agent: descriptor,
            policy: policy,
            startedAt: started,
            endedAt: ended,
            inputSummary: ["source": "memory"],
            selectedIds: ["m-1", "m-2"],
            omittedIds: ["m-3"],
            fallbackReason: "budget_exhausted",
            toolUsage: [
                AgentToolUsage(
                    toolName: "local-ranker",
                    callCount: 1,
                    inputSummary: "3 candidates",
                    outputSummary: "2 selected"
                )
            ],
            tokenUsage: AgentTokenUsage(
                inputTokens: 42,
                outputTokens: 7,
                totalTokens: 49
            ),
            schemaValidation: SchemaValidationResult(
                isValid: false,
                repaired: true,
                errors: ["missing confidence"]
            ),
            errors: [
                AgentDiagnosticError(
                    code: "fallback",
                    message: "Used deterministic fallback."
                )
            ]
        )

        #expect(diagnostics.taskName == "DiagnosticsTask")
        #expect(diagnostics.agent == descriptor)
        #expect(diagnostics.policy == policy)
        #expect(diagnostics.startedAt == started)
        #expect(diagnostics.endedAt == ended)
        #expect(diagnostics.inputSummary["source"] == "memory")
        #expect(diagnostics.selectedIds == ["m-1", "m-2"])
        #expect(diagnostics.omittedIds == ["m-3"])
        #expect(diagnostics.fallbackReason == "budget_exhausted")
        #expect(diagnostics.toolUsage.first?.toolName == "local-ranker")
        #expect(diagnostics.toolUsage.first?.callCount == 1)
        #expect(diagnostics.tokenUsage?.totalTokens == 49)
        #expect(diagnostics.schemaValidation?.isValid == false)
        #expect(diagnostics.schemaValidation?.repaired == true)
        #expect(diagnostics.schemaValidation?.errors == ["missing confidence"])
        #expect(diagnostics.errors == [
            AgentDiagnosticError(
                code: "fallback",
                message: "Used deterministic fallback."
            )
        ])
    }

    @Test func test_diagnostics_canRepresentOmittedOptionalFields() {
        let descriptor = AgentDescriptor(
            id: "minimal.agent",
            kind: .conversationStateTracker,
            displayName: "Minimal",
            version: "1.0.0",
            purpose: "Records minimal diagnostics."
        )
        let diagnostics = AgentDiagnostics.make(
            taskName: "MinimalTask",
            agent: descriptor,
            policy: AgentPolicy.backgroundWorkerDefault(),
            startedAt: Date(timeIntervalSince1970: 10)
        )

        #expect(diagnostics.endedAt == nil)
        #expect(diagnostics.inputSummary.isEmpty)
        #expect(diagnostics.selectedIds.isEmpty)
        #expect(diagnostics.omittedIds.isEmpty)
        #expect(diagnostics.fallbackReason == nil)
        #expect(diagnostics.toolUsage.isEmpty)
        #expect(diagnostics.tokenUsage == nil)
        #expect(diagnostics.schemaValidation == nil)
        #expect(diagnostics.errors.isEmpty)
    }
}
