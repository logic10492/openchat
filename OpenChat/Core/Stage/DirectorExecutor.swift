import Foundation

protocol DirectorExecuting: Sendable {
    func execute(_ input: DirectorRuntimeInput) async throws -> StageTurnPlan
}

struct DirectorRuntimeInput: Sendable, Equatable {
    let stageContext: StageContext
    let inputRole: StageInputRole
    let currentInput: String
    let now: Date

    init(
        stageContext: StageContext,
        inputRole: StageInputRole,
        currentInput: String,
        now: Date = .now
    ) {
        self.stageContext = stageContext
        self.inputRole = inputRole
        self.currentInput = currentInput
        self.now = now
    }
}

struct DeterministicDirectorExecutor: DirectorExecuting {
    private let controller = DirectorController()

    func execute(_ input: DirectorRuntimeInput) async throws -> StageTurnPlan {
        try controller.planTurn(
            stageContext: input.stageContext,
            inputRole: input.inputRole,
            currentInput: input.currentInput,
            now: input.now
        )
    }
}

struct LLMDirectorExecutor: DirectorExecuting {
    private let agentExecutor: any AgentExecutor
    private let apiClient: APIClient
    private let endpoint: APIEndpointConfig
    private let parameters: ModelParameters
    private let fallback: DeterministicDirectorExecutor

    init(
        agentExecutor: any AgentExecutor = LLMAgentExecutor(),
        apiClient: APIClient,
        endpoint: APIEndpointConfig,
        parameters: ModelParameters,
        fallback: DeterministicDirectorExecutor = DeterministicDirectorExecutor()
    ) {
        self.agentExecutor = agentExecutor
        self.apiClient = apiClient
        self.endpoint = endpoint
        self.parameters = parameters
        self.fallback = fallback
    }

    func execute(_ input: DirectorRuntimeInput) async throws -> StageTurnPlan {
        if input.inputRole.isDirectorInstructionInput {
            return try await fallback.execute(input)
        }

        let fallbackPlan = try await fallback.execute(input)
        guard input.stageContext.stage.directorModeValue == .agent else {
            return fallbackPlan
        }

        let task = LLMDirectorTask(
            apiClient: apiClient,
            endpoint: endpoint,
            parameters: parameters,
            fallbackPlan: fallbackPlan
        )
        let result = try await agentExecutor.execute(
            task: task,
            input: input,
            context: AgentExecutionContext(
                requestId: input.stageContext.stage.id,
                now: input.now,
                localeIdentifier: Locale.current.identifier
            )
        )
        return result.output
    }
}
