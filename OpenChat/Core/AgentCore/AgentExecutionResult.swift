import Foundation

struct AgentExecutionResult<Output: Sendable>: Sendable {
    let output: Output
    let diagnostics: AgentDiagnostics
}
