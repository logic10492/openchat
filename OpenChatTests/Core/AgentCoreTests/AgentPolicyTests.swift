import Foundation
import Testing

@testable import OpenChat

@Suite("Agent policy")
struct AgentPolicyTests {
    @Test func test_backgroundWorkerDefault_deniesLLMWebAndDatabaseWrite() {
        let policy = AgentPolicy.backgroundWorkerDefault()

        #expect(policy.allowedCapabilities.contains(.deterministic))
        #expect(policy.allowedCapabilities.contains(.internalDiagnostics))
        #expect(!policy.allowedCapabilities.contains(.llm))
        #expect(!policy.allowedCapabilities.contains(.webSearch))
        #expect(!policy.allowedCapabilities.contains(.databaseWrite))
        #expect(!policy.toolUsePolicy.allowNetwork)
        #expect(!policy.sideEffectPolicy.allowDatabaseWrite)
    }

    @Test func test_directorDefault_canOptionallyAllowLLM_butNeverWebOrDatabaseWrite() {
        let deterministicDirector = AgentPolicy.directorDefault()
        let llmDirector = AgentPolicy.directorDefault(allowsLLM: true)

        #expect(!deterministicDirector.allowedCapabilities.contains(.llm))
        #expect(llmDirector.allowedCapabilities.contains(.llm))

        for policy in [deterministicDirector, llmDirector] {
            #expect(!policy.allowedCapabilities.contains(.webSearch))
            #expect(!policy.allowedCapabilities.contains(.databaseWrite))
            #expect(!policy.toolUsePolicy.allowNetwork)
            #expect(!policy.sideEffectPolicy.allowDatabaseWrite)
        }
    }

    @Test func test_directorDefault_deterministicHasNoLLMAndNoExternalEffects() {
        let policy = AgentPolicy.directorDefault()

        #expect(policy.allowedCapabilities.contains(.deterministic))
        #expect(policy.allowedCapabilities.contains(.internalDiagnostics))
        #expect(!policy.allowedCapabilities.contains(.llm))
        #expect(!policy.allowedCapabilities.contains(.webSearch))
        #expect(!policy.allowedCapabilities.contains(.databaseWrite))
        #expect(!policy.allowedCapabilities.contains(.userVisibleDraft))
        #expect(!policy.toolUsePolicy.allowNetwork)
        #expect(policy.toolUsePolicy.allowedToolNames.isEmpty)
        #expect(!policy.sideEffectPolicy.allowDatabaseWrite)
        #expect(policy.confirmationPolicy.requiredForPersistentWrite)
        #expect(!policy.visibilityPolicy.exposeDraftToUser)
    }

    @Test func test_directorDefault_llmStillDeniesNetworkToolsAndPersistentWrites() {
        let policy = AgentPolicy.directorDefault(allowsLLM: true)

        #expect(policy.allowedCapabilities.contains(.llm))
        #expect(!policy.allowedCapabilities.contains(.webSearch))
        #expect(!policy.allowedCapabilities.contains(.databaseWrite))
        #expect(!policy.allowedCapabilities.contains(.userVisibleDraft))
        #expect(!policy.toolUsePolicy.allowNetwork)
        #expect(policy.toolUsePolicy.allowedToolNames.isEmpty)
        #expect(!policy.sideEffectPolicy.allowDatabaseWrite)
        #expect(policy.confirmationPolicy.requiredForPersistentWrite)
        #expect(!policy.visibilityPolicy.exposeDraftToUser)
    }

    @Test func test_librarianDraftDefault_allowsWebDraft_butRequiresPersistentWriteConfirmation() {
        let policy = AgentPolicy.librarianDraftDefault()

        #expect(policy.allowedCapabilities.contains(.llm))
        #expect(policy.allowedCapabilities.contains(.webSearch))
        #expect(policy.allowedCapabilities.contains(.userVisibleDraft))
        #expect(policy.toolUsePolicy.allowNetwork)
        #expect(policy.toolUsePolicy.allowedToolNames == ["exa"])
        #expect(policy.toolUsePolicy.requireCitations)
        #expect(!policy.sideEffectPolicy.allowDatabaseWrite)
        #expect(policy.confirmationPolicy.requiredForDraftApply)
        #expect(policy.confirmationPolicy.requiredForPersistentWrite)
    }

    @Test func test_librarianDraftOfflineDefault_allowsVisibleDraft_butDeniesNetworkAndWrites() {
        let policy = AgentPolicy.librarianDraftOfflineDefault()

        #expect(policy.allowedCapabilities.contains(.llm))
        #expect(policy.allowedCapabilities.contains(.userVisibleDraft))
        #expect(!policy.allowedCapabilities.contains(.webSearch))
        #expect(!policy.allowedCapabilities.contains(.databaseWrite))
        #expect(!policy.toolUsePolicy.allowNetwork)
        #expect(policy.toolUsePolicy.allowedToolNames.isEmpty)
        #expect(!policy.sideEffectPolicy.allowDatabaseWrite)
        #expect(policy.confirmationPolicy.requiredForDraftApply)
        #expect(policy.confirmationPolicy.requiredForPersistentWrite)
    }

    @Test func test_llmAgentExecutor_allowsOfflineLibrarianDraftPolicy() async throws {
        let result = try await LLMAgentExecutor().execute(
            task: NoopLibrarianDraftTask(),
            input: "draft",
            context: AgentExecutionContext(
                requestId: "policy-test",
                now: Date(timeIntervalSince1970: 1),
                localeIdentifier: "en_US"
            )
        )

        #expect(result.output == "draft")
    }

    @Test func test_reflectDefault_allowsLLMAndDatabaseRead_butDeniesWebAndDatabaseWrite() {
        let policy = AgentPolicy.reflectDefault()

        #expect(policy.allowedCapabilities.contains(.llm))
        #expect(policy.allowedCapabilities.contains(.databaseRead))
        #expect(policy.allowedCapabilities.contains(.internalDiagnostics))
        #expect(!policy.allowedCapabilities.contains(.webSearch))
        #expect(!policy.allowedCapabilities.contains(.databaseWrite))
        #expect(!policy.toolUsePolicy.allowNetwork)
        #expect(policy.sideEffectPolicy.allowDatabaseRead)
        #expect(!policy.sideEffectPolicy.allowDatabaseWrite)
        #expect(policy.confirmationPolicy.requiredForPersistentWrite)
    }
}

private struct NoopLibrarianDraftTask: AgentTask {
    let descriptor = AgentDescriptor(
        id: "test.librarian.noop",
        kind: .librarian,
        displayName: "Noop Librarian",
        version: "0",
        purpose: "Test offline librarian policy validation."
    )
    let policy = AgentPolicy.librarianDraftOfflineDefault()

    func run(input: String, context: AgentExecutionContext) async throws -> AgentExecutionResult<String> {
        AgentExecutionResult(
            output: input,
            diagnostics: AgentDiagnostics.make(
                taskName: "noop",
                agent: descriptor,
                policy: policy,
                startedAt: context.now
            )
        )
    }
}
