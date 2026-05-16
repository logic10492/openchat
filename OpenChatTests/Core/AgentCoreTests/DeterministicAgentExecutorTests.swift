import Foundation
import Testing

@testable import OpenChat

@Suite("Deterministic agent executor")
struct DeterministicAgentExecutorTests {
    @Test func test_execute_runsDeterministicTask_andPreservesDiagnosticsPolicy() async throws {
        let policy = AgentPolicy(
            allowedCapabilities: [.deterministic, .internalDiagnostics],
            tokenBudget: AgentTokenBudget(maxInputTokens: 100, maxOutputTokens: 20, maxTotalTokens: 120),
            timeoutSeconds: 7.5,
            retryPolicy: AgentRetryPolicy(maxAttempts: 3, retryDelaySeconds: 0.25),
            schemaRepairPolicy: SchemaRepairPolicy(allowRepair: false, maxRepairAttempts: 0),
            visibilityPolicy: AgentVisibilityPolicy(exposeDiagnosticsToUser: false, exposeDraftToUser: false),
            toolUsePolicy: .disabled,
            sideEffectPolicy: .readOnly,
            confirmationPolicy: ConfirmationPolicy(
                requiredForDraftApply: false,
                requiredForPersistentWrite: true
            )
        )
        let task = EchoAgentTask(policy: policy)
        let context = makeContext()

        let result = try await DeterministicAgentExecutor().execute(
            task: task,
            input: "alpha beta gamma",
            context: context
        )

        #expect(result.output == "ALPHA BETA GAMMA")
        #expect(result.diagnostics.taskName == "EchoAgentTask")
        #expect(result.diagnostics.policy.timeoutSeconds == 7.5)
        #expect(result.diagnostics.policy.retryPolicy.maxAttempts == 3)
        #expect(result.diagnostics.policy.tokenBudget.maxTotalTokens == 120)
        #expect(result.diagnostics.inputSummary["characterCount"] == "16")
        #expect(result.diagnostics.selectedIds == ["alpha", "beta"])
        #expect(result.diagnostics.omittedIds == ["gamma"])
    }

    @Test func test_execute_rejectsLLMCapability() async throws {
        let task = EchoAgentTask(policy: policy(allowedCapabilities: [.deterministic, .llm]))

        await expectAgentError(.capabilityDenied(agentId: "test.echo", capability: .llm)) {
            _ = try await DeterministicAgentExecutor().execute(
                task: task,
                input: "hello",
                context: makeContext()
            )
        }
    }

    @Test func test_execute_rejectsWebSearchCapability_orNetworkTools() async throws {
        let webTask = EchoAgentTask(policy: policy(allowedCapabilities: [.deterministic, .webSearch]))

        await expectAgentError(.capabilityDenied(agentId: "test.echo", capability: .webSearch)) {
            _ = try await DeterministicAgentExecutor().execute(
                task: webTask,
                input: "hello",
                context: makeContext()
            )
        }

        let networkPolicy = policy(
            toolUsePolicy: ToolUsePolicy(
                allowedToolNames: ["exa"],
                allowNetwork: true,
                requireCitations: true
            )
        )
        let networkTask = EchoAgentTask(policy: networkPolicy)

        await expectAgentError(.networkDenied(agentId: "test.echo")) {
            _ = try await DeterministicAgentExecutor().execute(
                task: networkTask,
                input: "hello",
                context: makeContext()
            )
        }
    }

    @Test func test_execute_rejectsDatabaseWriteSideEffect() async throws {
        let writePolicy = policy(
            sideEffectPolicy: SideEffectPolicy(
                allowDatabaseRead: false,
                allowDatabaseWrite: true,
                requiresUserConfirmationForWrite: true
            )
        )
        let task = EchoAgentTask(policy: writePolicy)

        await expectAgentError(.databaseWriteDenied(agentId: "test.echo")) {
            _ = try await DeterministicAgentExecutor().execute(
                task: task,
                input: "hello",
                context: makeContext()
            )
        }
    }

    @Test func test_agentError_localizedDescription_isReadable() {
        let error = AgentError.capabilityDenied(agentId: "agent-a", capability: .llm)

        #expect(error.localizedDescription == "Agent agent-a is not allowed to use capability llm.")
    }
}

private struct EchoAgentTask: AgentTask {
    let descriptor = AgentDescriptor(
        id: "test.echo",
        kind: .backgroundWorker,
        displayName: "Echo",
        version: "1.0.0",
        purpose: "Echoes uppercase input."
    )
    let policy: AgentPolicy

    func run(input: String, context: AgentExecutionContext) async throws -> AgentExecutionResult<String> {
        let diagnostics = AgentDiagnostics.make(
            taskName: "EchoAgentTask",
            agent: descriptor,
            policy: policy,
            startedAt: context.now,
            endedAt: context.now.addingTimeInterval(0.1),
            inputSummary: ["characterCount": "\(input.count)"],
            selectedIds: ["alpha", "beta"],
            omittedIds: ["gamma"],
            fallbackReason: nil,
            tokenUsage: AgentTokenUsage(
                inputTokens: 3,
                outputTokens: 3,
                totalTokens: 6
            )
        )

        return AgentExecutionResult(output: input.uppercased(), diagnostics: diagnostics)
    }
}

private func makeContext() -> AgentExecutionContext {
    AgentExecutionContext(
        requestId: "request-1",
        now: Date(timeIntervalSince1970: 1_000),
        localeIdentifier: "en_US"
    )
}

private func policy(
    allowedCapabilities: Set<AgentCapability> = [.deterministic, .internalDiagnostics],
    toolUsePolicy: ToolUsePolicy = .disabled,
    sideEffectPolicy: SideEffectPolicy = .readOnly
) -> AgentPolicy {
    AgentPolicy(
        allowedCapabilities: allowedCapabilities,
        tokenBudget: AgentTokenBudget(maxInputTokens: 100, maxOutputTokens: 20, maxTotalTokens: 120),
        timeoutSeconds: 5,
        retryPolicy: AgentRetryPolicy(maxAttempts: 1, retryDelaySeconds: 0),
        schemaRepairPolicy: SchemaRepairPolicy(allowRepair: false, maxRepairAttempts: 0),
        visibilityPolicy: AgentVisibilityPolicy(exposeDiagnosticsToUser: false, exposeDraftToUser: false),
        toolUsePolicy: toolUsePolicy,
        sideEffectPolicy: sideEffectPolicy,
        confirmationPolicy: ConfirmationPolicy(
            requiredForDraftApply: false,
            requiredForPersistentWrite: true
        )
    )
}

private func expectAgentError(
    _ expectedError: AgentError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        #expect(Bool(false), "Expected \(expectedError), but operation completed successfully.")
    } catch let error as AgentError {
        #expect(error == expectedError)
    } catch {
        #expect(Bool(false), "Expected \(expectedError), but got \(error).")
    }
}
