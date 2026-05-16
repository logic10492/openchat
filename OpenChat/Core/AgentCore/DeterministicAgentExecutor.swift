import Foundation

struct DeterministicAgentExecutor: AgentExecutor {
    let supportedCapabilities: Set<AgentCapability> = [
        .deterministic,
        .internalDiagnostics
    ]

    func execute<Task: AgentTask>(
        task: Task,
        input: Task.Input,
        context: AgentExecutionContext
    ) async throws -> AgentExecutionResult<Task.Output> {
        try validate(task: task)

        do {
            return try await task.run(input: input, context: context)
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.executionFailed(
                agentId: task.descriptor.id,
                message: error.localizedDescription
            )
        }
    }

    private func validate<Task: AgentTask>(task: Task) throws {
        for capability in task.policy.allowedCapabilities where !supportedCapabilities.contains(capability) {
            throw AgentError.capabilityDenied(
                agentId: task.descriptor.id,
                capability: capability
            )
        }

        if task.policy.toolUsePolicy.allowNetwork {
            throw AgentError.networkDenied(agentId: task.descriptor.id)
        }

        if task.policy.sideEffectPolicy.allowDatabaseWrite {
            throw AgentError.databaseWriteDenied(agentId: task.descriptor.id)
        }
    }
}
