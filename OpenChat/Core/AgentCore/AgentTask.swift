import Foundation

protocol AgentTask: Sendable {
    associatedtype Input: Sendable
    associatedtype Output: Sendable

    var descriptor: AgentDescriptor { get }
    var policy: AgentPolicy { get }

    func run(input: Input, context: AgentExecutionContext) async throws -> AgentExecutionResult<Output>
}
