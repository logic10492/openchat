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
}
