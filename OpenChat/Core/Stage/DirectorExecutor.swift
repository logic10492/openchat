import Foundation

protocol DirectorExecuting: Sendable {
    func execute(_ input: DirectorRuntimeInput) throws -> StageTurnPlan
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

    func execute(_ input: DirectorRuntimeInput) throws -> StageTurnPlan {
        try controller.planTurn(
            stageContext: input.stageContext,
            inputRole: input.inputRole,
            currentInput: input.currentInput,
            now: input.now
        )
    }
}
