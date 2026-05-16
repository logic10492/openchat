import Foundation

protocol AgentExecutor: Sendable {
    func execute<Task: AgentTask>(
        task: Task,
        input: Task.Input,
        context: AgentExecutionContext
    ) async throws -> AgentExecutionResult<Task.Output>
}
